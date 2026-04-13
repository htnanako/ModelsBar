import Foundation

struct ModelTestRequest: Equatable, Hashable {
    var providerID: UUID
    var keyID: UUID
    var modelID: String
    var mode: TestMode
}

enum ModelTestExecutionState: Equatable {
    case idle
    case queued
    case running
}

enum ModelAggregateVisualState: Equatable {
    case idle
    case success
    case mixed
    case failure
}

@MainActor
final class ModelsBarState: ObservableObject {
    @Published var data: AppData
    @Published var selectedProviderID: UUID?
    @Published var isWorking = false
    @Published var statusMessage = "就绪"
    @Published var revealsKeys = false
    @Published private(set) var workingProviderIDs: Set<UUID> = []
    @Published private(set) var activeModelTestRequest: ModelTestRequest?
    @Published private(set) var queuedModelTestRequests: [ModelTestRequest] = []

    let store: ModelsBarStore
    private var schedulerTask: Task<Void, Never>?
    private var modelTestQueueTask: Task<Void, Never>?

    init(store: ModelsBarStore = ModelsBarStore()) {
        self.store = store
        data = store.load()
        selectedProviderID = data.providers.first?.id
    }

    var enabledKeyCount: Int {
        data.providers.flatMap(\.keys).filter(\.isEnabled).count
    }

    var failedKeyCount: Int {
        data.providers.flatMap(\.keys).filter { $0.lastStatus == .failed }.count
    }

    var healthyKeyCount: Int {
        data.providers.flatMap(\.keys).filter { $0.lastStatus == .healthy }.count
    }

    var syncableProviderCount: Int {
        data.providers.filter { syncSupportedProviderTypes.contains($0.type) }.count
    }

    func startDailyQuotaScheduler() {
        guard schedulerTask == nil else {
            return
        }

        schedulerTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                await self?.recordMissingDailyQuotaSnapshots()
                try? await Task.sleep(for: .seconds(21_600))
            }
        }
    }

    func provider(id: UUID) -> ProviderConfig? {
        data.providers.first { $0.id == id }
    }

    func providerStatusMessage(for providerID: UUID) -> String {
        let message = provider(id: providerID)?.lastStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? "就绪" : message
    }

    func isProviderWorking(_ providerID: UUID) -> Bool {
        workingProviderIDs.contains(providerID)
    }

    func modelTestExecutionState(providerID: UUID, keyID: UUID, modelID: String, mode: TestMode) -> ModelTestExecutionState {
        let request = ModelTestRequest(providerID: providerID, keyID: keyID, modelID: modelID, mode: mode)
        if activeModelTestRequest == request {
            return .running
        }

        if queuedModelTestRequests.contains(request) {
            return .queued
        }

        return .idle
    }

    func key(providerID: UUID, keyID: UUID) -> APIKeyConfig? {
        provider(id: providerID)?.keys.first { $0.id == keyID }
    }

    func modelRecords(providerID: UUID, keyID: UUID? = nil) -> [ModelRecord] {
        data.modelRecords
            .filter { record in
                record.providerID == providerID && (keyID == nil || record.keyID == keyID)
            }
            .sorted { $0.modelID.localizedStandardCompare($1.modelID) == .orderedAscending }
    }

    func uniqueModelCount(providerID: UUID) -> Int {
        Set(data.modelRecords
            .filter { $0.providerID == providerID }
            .map(\.modelID)
        ).count
    }

    func quotaRecords(providerID: UUID? = nil, keyID: UUID? = nil) -> [QuotaDailyRecord] {
        data.quotaRecords
            .filter { record in
                (providerID == nil || record.providerID == providerID) &&
                    (keyID == nil || record.keyID == keyID)
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    @discardableResult
    func addProvider(type: ProviderType = .newapi, name: String, baseURL: String) -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = ProviderConfig(
            type: type,
            name: trimmedName.isEmpty ? type.defaultProviderName : trimmedName,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        data.providers.append(provider)
        selectedProviderID = provider.id
        persist()
        return provider.id
    }

    @discardableResult
    func addProvider(type: ProviderType = .newapi, name: String, baseURL: String, managementToken: String, managementUserID: String) -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedManagementToken = managementToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserID = managementUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = ProviderConfig(
            type: type,
            name: trimmedName.isEmpty ? type.defaultProviderName : trimmedName,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            managementToken: type == .newapi && trimmedManagementToken.isEmpty == false ? trimmedManagementToken : nil,
            managementUserID: type == .newapi && trimmedUserID.isEmpty == false ? trimmedUserID : nil
        )
        data.providers.append(provider)
        selectedProviderID = provider.id
        persist()
        return provider.id
    }

    @discardableResult
    func addSub2APIProvider(name: String, baseURL: String, authorization: Sub2APIAuthorizationSession) -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = ProviderConfig(
            type: .sub2api,
            name: trimmedName.isEmpty ? ProviderType.sub2api.defaultProviderName : trimmedName,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            sub2APIAccessToken: authorization.accessToken,
            sub2APIRefreshToken: authorization.refreshToken,
            sub2APITokenExpiresAt: authorization.tokenExpiresAt,
            sub2APIUser: authorization.user
        )
        data.providers.append(provider)
        selectedProviderID = provider.id
        persist()
        return provider.id
    }

    func clearProviderSyncResults(_ providerID: UUID) {
        data.modelRecords.removeAll { $0.providerID == providerID }
        data.quotaRecords.removeAll { $0.providerID == providerID }
        data.testResults.removeAll { $0.providerID == providerID }
        persist()
    }

    func deleteProvider(_ providerID: UUID) {
        data.providers.removeAll { $0.id == providerID }
        data.modelRecords.removeAll { $0.providerID == providerID }
        data.quotaRecords.removeAll { $0.providerID == providerID }
        data.testResults.removeAll { $0.providerID == providerID }
        if selectedProviderID == providerID {
            selectedProviderID = data.providers.first?.id
        }
        persist()
    }

    func updateProvider(_ providerID: UUID, mutate: (inout ProviderConfig) -> Void) {
        guard let index = data.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }

        mutate(&data.providers[index])
        data.providers[index].updatedAt = .now
        persist()
    }

    func moveProvider(_ providerID: UUID, toIndex destinationIndex: Int) {
        guard let sourceIndex = data.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }

        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        let clampedDestination = min(max(0, adjustedDestination), data.providers.count - 1)
        guard clampedDestination != sourceIndex else {
            return
        }

        let provider = data.providers.remove(at: sourceIndex)
        data.providers.insert(provider, at: clampedDestination)
        persist()
    }

    func addKey(providerID: UUID, name: String, value: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updateProvider(providerID) { provider in
            provider.keys.append(APIKeyConfig(
                name: trimmedName.isEmpty ? "Default Token" : trimmedName,
                value: value.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
    }

    func deleteKey(providerID: UUID, keyID: UUID) {
        updateProvider(providerID) { provider in
            provider.keys.removeAll { $0.id == keyID }
        }
        data.modelRecords.removeAll { $0.keyID == keyID }
        data.quotaRecords.removeAll { $0.keyID == keyID }
        data.testResults.removeAll { $0.keyID == keyID }
        persist()
    }

    func updateKey(providerID: UUID, keyID: UUID, mutate: (inout APIKeyConfig) -> Void) {
        guard let providerIndex = data.providers.firstIndex(where: { $0.id == providerID }),
              let keyIndex = data.providers[providerIndex].keys.firstIndex(where: { $0.id == keyID }) else {
            return
        }

        mutate(&data.providers[providerIndex].keys[keyIndex])
        data.providers[providerIndex].keys[keyIndex].updatedAt = .now
        data.providers[providerIndex].updatedAt = .now
        persist()
    }

    func completeManualKey(providerID: UUID, keyID: UUID, value: String) {
        guard let provider = provider(id: providerID), provider.type == .newapi else {
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("sk-") ? String(trimmed.dropFirst(3)) : trimmed
        guard normalized.isEmpty == false else {
            return
        }

        updateKey(providerID: providerID, keyID: keyID) { key in
            key.value = normalized
            key.requiresManualCompletion = false
            key.lastStatus = .unknown
            key.lastMessage = "已手动补全 Key，等待刷新"
            key.updatedAt = .now
        }

        let remainingManualCount = self.provider(id: providerID)?.keys.filter(\.requiresManualCompletion).count ?? 0
        updateProvider(providerID) { provider in
            provider.requiresManualKeyCompletion = remainingManualCount > 0
            provider.lastStatusMessage = remainingManualCount > 0
                ? "还有 \(remainingManualCount) 个 Key 需要手动补全"
                : nil
        }
        statusMessage = remainingManualCount > 0
            ? "已补全 Key，还有 \(remainingManualCount) 个待补全"
            : "已补全 Key，请刷新额度和模型"
    }

    func moveKey(providerID: UUID, keyID: UUID, before targetKeyID: UUID) {
        guard keyID != targetKeyID,
              let providerIndex = data.providers.firstIndex(where: { $0.id == providerID }),
              let sourceIndex = data.providers[providerIndex].keys.firstIndex(where: { $0.id == keyID }),
              let targetIndex = data.providers[providerIndex].keys.firstIndex(where: { $0.id == targetKeyID }) else {
            return
        }

        let key = data.providers[providerIndex].keys.remove(at: sourceIndex)
        let adjustedTargetIndex = min(targetIndex, data.providers[providerIndex].keys.count)
        data.providers[providerIndex].keys.insert(key, at: adjustedTargetIndex)
        data.providers[providerIndex].updatedAt = .now
        persist()
    }

    func moveKey(providerID: UUID, keyID: UUID, toIndex destinationIndex: Int) {
        guard let providerIndex = data.providers.firstIndex(where: { $0.id == providerID }),
              let sourceIndex = data.providers[providerIndex].keys.firstIndex(where: { $0.id == keyID }) else {
            return
        }

        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        let clampedDestination = min(max(0, adjustedDestination), data.providers[providerIndex].keys.count - 1)
        guard clampedDestination != sourceIndex else {
            return
        }

        let key = data.providers[providerIndex].keys.remove(at: sourceIndex)
        data.providers[providerIndex].keys.insert(key, at: clampedDestination)
        data.providers[providerIndex].updatedAt = .now
        persist()
    }

    func refreshModels(providerID: UUID, keyID: UUID, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID), let apiKey = key(providerID: providerID, keyID: keyID) else {
            return
        }

        guard openAIGatewaySupportedProviderTypes.contains(provider.type) else {
            setStatus("\(provider.type.title) 暂未接入 OpenAI completions", providerID: providerID)
            return
        }

        if provider.type == .newapi && apiKey.requestValue(for: .newapi) == nil {
            updateKey(providerID: providerID, keyID: keyID) { key in
                key.lastStatus = .warning
                key.lastMessage = "请先手动补全完整 Key"
                key.lastCheckedAt = .now
            }
            setStatus("\(apiKey.name) 需要先手动补全 Key", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在刷新 \(apiKey.name) 的模型", providerID: providerID)

        do {
            let requestValue = apiKey.requestValue(for: provider.type) ?? apiKey.value
            let client = NewAPIClient(baseURLString: provider.baseURL, apiKey: requestValue)
            let models = try await client.fetchModels()
            upsertModels(providerID: providerID, keyID: keyID, modelIDs: models)
            updateKey(providerID: providerID, keyID: keyID) { key in
                key.lastStatus = .healthy
                key.lastMessage = "模型刷新成功：\(models.count) 个"
                key.lastCheckedAt = .now
            }
            setStatus("已刷新 \(models.count) 个模型", providerID: providerID)
        } catch {
            updateKey(providerID: providerID, keyID: keyID) { key in
                key.lastStatus = .failed
                key.lastMessage = error.localizedDescription
                key.lastCheckedAt = .now
            }
            setStatus(error.localizedDescription, providerID: providerID)
        }

    }

    func syncManagedTokens(providerID: UUID, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID) else {
            return
        }

        switch provider.type {
        case .newapi:
            await syncNewAPIManagedTokens(providerID: providerID, provider: provider, managesWorkingState: managesWorkingState)
        case .sub2api:
            await syncSub2APIManagedTokens(providerID: providerID, provider: provider, managesWorkingState: managesWorkingState)
        }
    }

    func syncAllManagedTokens() async {
        let providerIDs = data.providers
            .filter { syncSupportedProviderTypes.contains($0.type) }
            .map(\.id)
        guard providerIDs.isEmpty == false else {
            statusMessage = "还没有可同步站点"
            return
        }

        isWorking = true
        statusMessage = "正在同步全部站点"

        for providerID in providerIDs {
            beginProviderWork(providerID)
            await syncManagedTokens(providerID: providerID, managesWorkingState: false)
            endProviderWork(providerID)
        }

        statusMessage = "全部站点同步完成"
        isWorking = false
    }

    func refreshAccountQuota(providerID: UUID, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID) else {
            return
        }

        switch provider.type {
        case .newapi:
            await refreshNewAPIAccountQuota(providerID: providerID, provider: provider, managesWorkingState: managesWorkingState)
        case .sub2api:
            await refreshSub2APIAccountQuota(providerID: providerID, provider: provider, managesWorkingState: managesWorkingState)
        }
    }

    func refreshQuota(providerID: UUID, keyID: UUID, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID), let apiKey = key(providerID: providerID, keyID: keyID) else {
            return
        }

        switch provider.type {
        case .newapi:
            await refreshNewAPIQuota(providerID: providerID, provider: provider, apiKey: apiKey, managesWorkingState: managesWorkingState)
        case .sub2api:
            await refreshSub2APIQuota(providerID: providerID, provider: provider, apiKey: apiKey, managesWorkingState: managesWorkingState)
        }
    }

    func refreshKeyInfo(providerID: UUID, keyID: UUID, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID),
              let apiKey = key(providerID: providerID, keyID: keyID) else {
            return
        }

        if provider.type == .newapi && apiKey.requestValue(for: .newapi) == nil {
            updateKey(providerID: providerID, keyID: keyID) { key in
                key.lastStatus = .warning
                key.lastMessage = "请先手动补全完整 Key"
                key.lastCheckedAt = .now
            }
            setStatus("\(apiKey.name) 需要先手动补全 Key", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }

        setStatus("正在刷新 \(apiKey.name) 的额度和模型", providerID: providerID)
        await refreshQuota(providerID: providerID, keyID: keyID, managesWorkingState: false)
        await refreshModels(providerID: providerID, keyID: keyID, managesWorkingState: false)
        setStatus("\(apiKey.name) 的额度和模型已刷新", providerID: providerID)
    }

    func refreshTodayUsage(providerID: UUID, keyID: UUID, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID), let apiKey = key(providerID: providerID, keyID: keyID) else {
            return
        }

        guard provider.type == .newapi else {
            return
        }

        guard let managementToken = provider.managementToken,
              managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }

        do {
            let client = NewAPIClient(baseURLString: provider.baseURL, apiKey: "")
            let todayUsage = try await client.fetchTodayTokenUsage(
                accessToken: managementToken,
                userID: provider.managementUserID,
                tokenName: apiKey.name
            )
            updateKey(providerID: providerID, keyID: keyID) { key in
                key.todayUsedQuota = todayUsage
                key.todayUsageCheckedAt = .now
            }
        } catch {
            updateKey(providerID: providerID, keyID: keyID) { key in
                key.todayUsedQuota = nil
                key.todayUsageCheckedAt = .now
            }
            setStatus("今日消耗读取失败：\(error.localizedDescription)", providerID: providerID)
        }

    }

    func validateSub2APIAuthorization(
        baseURL: String,
        accessToken: String,
        refreshToken: String,
        tokenExpiresAt: Date?
    ) async throws -> Sub2APIAuthorizationSession {
        let client = Sub2APIClient(baseURLString: baseURL)
        let user = try await client.fetchCurrentUser(accessToken: accessToken)
        return Sub2APIAuthorizationSession(
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            refreshToken: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines),
            tokenExpiresAt: tokenExpiresAt,
            user: user
        )
    }

    func testModel(providerID: UUID, keyID: UUID, modelID: String, mode: TestMode, managesWorkingState: Bool = true) async {
        guard let provider = provider(id: providerID), let apiKey = key(providerID: providerID, keyID: keyID) else {
            return
        }

        guard openAIGatewaySupportedProviderTypes.contains(provider.type) else {
            setStatus("\(provider.type.title) 暂未接入 OpenAI completions", providerID: providerID)
            return
        }

        if provider.type == .newapi && apiKey.requestValue(for: .newapi) == nil {
            setStatus("\(apiKey.name) 需要先手动补全 Key", providerID: providerID)
            return
        }

        let modelInterface = OpenAIModelInterface(modelID: modelID)
        if mode == .stream && modelInterface.supportsStreamTesting == false {
            setStatus("\(modelID) 不支持流式测试", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在测试 \(modelID)（\(mode.title)）", providerID: providerID)

        do {
            let requestValue = apiKey.requestValue(for: provider.type) ?? apiKey.value
            let client = NewAPIClient(baseURLString: provider.baseURL, apiKey: requestValue)
            let outcome = try await client.testModelConnectivity(modelID: modelID, mode: mode)
            let result = ModelTestResult(
                providerID: providerID,
                keyID: keyID,
                modelID: modelID,
                mode: mode,
                succeeded: true,
                latencyMS: outcome.latencyMS,
                message: outcome.message
            )
            storeTestResult(result)
            setStatus("\(modelID) 测试成功", providerID: providerID)
        } catch {
            let result = ModelTestResult(
                providerID: providerID,
                keyID: keyID,
                modelID: modelID,
                mode: mode,
                succeeded: false,
                latencyMS: 0,
                message: error.localizedDescription
            )
            storeTestResult(result)
            setStatus("\(modelID) 测试失败：\(error.localizedDescription)", providerID: providerID)
        }

    }

    func enqueueModelTest(providerID: UUID, keyID: UUID, modelID: String, mode: TestMode) {
        let request = ModelTestRequest(providerID: providerID, keyID: keyID, modelID: modelID, mode: mode)
        guard activeModelTestRequest != request,
              queuedModelTestRequests.contains(request) == false else {
            return
        }

        queuedModelTestRequests.append(request)
        startModelTestQueueIfNeeded()
    }

    func smokeTestAllModels() async {
        await runBatch(label: "测试全部模型") {
            let records = data.modelRecords
            for record in records {
                guard provider(id: record.providerID)?.isEnabled == true,
                      key(providerID: record.providerID, keyID: record.keyID)?.isEnabled == true else {
                    continue
                }

                await testModel(
                    providerID: record.providerID,
                    keyID: record.keyID,
                    modelID: record.modelID,
                    mode: .nonStream,
                    managesWorkingState: false
                )

                if OpenAIModelInterface(modelID: record.modelID).supportsStreamTesting {
                    await testModel(
                        providerID: record.providerID,
                        keyID: record.keyID,
                        modelID: record.modelID,
                        mode: .stream,
                        managesWorkingState: false
                    )
                }
            }
        }
    }

    func smokeTestProviderModels(providerID: UUID) async {
        await runBatch(label: "测试站点模型", providerID: providerID) {
            let records = data.modelRecords.filter { $0.providerID == providerID }
            for record in records {
                guard provider(id: record.providerID)?.isEnabled == true,
                      key(providerID: record.providerID, keyID: record.keyID)?.isEnabled == true else {
                    continue
                }

                await testModel(
                    providerID: record.providerID,
                    keyID: record.keyID,
                    modelID: record.modelID,
                    mode: .nonStream,
                    managesWorkingState: false
                )

                if OpenAIModelInterface(modelID: record.modelID).supportsStreamTesting {
                    await testModel(
                        providerID: record.providerID,
                        keyID: record.keyID,
                        modelID: record.modelID,
                        mode: .stream,
                        managesWorkingState: false
                    )
                }
            }
        }
    }

    func recordMissingDailyQuotaSnapshots() async {
        let today = Self.dayString(for: .now)
        for provider in data.providers where provider.isEnabled && provider.type == .newapi {
            for key in provider.keys where key.isEnabled {
                let exists = data.quotaRecords.contains {
                    $0.providerID == provider.id && $0.keyID == key.id && $0.day == today
                }

                if exists == false {
                    await refreshQuota(providerID: provider.id, keyID: key.id, managesWorkingState: false)
                }
            }
        }
    }

    private func runBatch(label: String, providerID: UUID? = nil, operation: () async -> Void) async {
        isWorking = true
        if let providerID {
            beginProviderWork(providerID)
            setStatus("\(label)中", providerID: providerID)
        } else {
            statusMessage = "\(label)中"
        }
        await operation()
        if let providerID {
            setStatus("\(label)完成", providerID: providerID)
            endProviderWork(providerID)
        } else {
            statusMessage = "\(label)完成"
        }
        isWorking = false
    }

    private var syncSupportedProviderTypes: Set<ProviderType> {
        [.newapi, .sub2api]
    }

    private var openAIGatewaySupportedProviderTypes: Set<ProviderType> {
        [.newapi, .sub2api]
    }

    private func setStatus(_ message: String, providerID: UUID? = nil) {
        statusMessage = message

        guard let providerID else {
            return
        }

        updateProvider(providerID) { provider in
            provider.lastStatusMessage = message
        }
    }

    private func beginProviderWork(_ providerID: UUID) {
        workingProviderIDs.insert(providerID)
    }

    private func endProviderWork(_ providerID: UUID) {
        workingProviderIDs.remove(providerID)
    }

    private func startModelTestQueueIfNeeded() {
        guard modelTestQueueTask == nil else {
            return
        }

        modelTestQueueTask = Task { @MainActor [weak self] in
            await self?.processModelTestQueue()
        }
    }

    private func processModelTestQueue() async {
        while queuedModelTestRequests.isEmpty == false {
            let request = queuedModelTestRequests.removeFirst()
            activeModelTestRequest = request
            beginProviderWork(request.providerID)
            await testModel(
                providerID: request.providerID,
                keyID: request.keyID,
                modelID: request.modelID,
                mode: request.mode,
                managesWorkingState: false
            )
            endProviderWork(request.providerID)
            activeModelTestRequest = nil
        }

        modelTestQueueTask = nil
    }

    private func syncNewAPIManagedTokens(providerID: UUID, provider: ProviderConfig, managesWorkingState: Bool) async {
        guard let managementToken = provider.managementToken,
              managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setStatus("请先配置系统访问令牌", providerID: providerID)
            return
        }

        guard let managementUserID = provider.managementUserID,
              managementUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setStatus("请先配置用户ID", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在同步 \(provider.name) 的令牌", providerID: providerID)

        do {
            let client = NewAPIClient(baseURLString: provider.baseURL, apiKey: "")
            await refreshAccountQuota(providerID: providerID, managesWorkingState: false)
            let tokens = try await client.fetchManagedTokens(
                accessToken: managementToken,
                userID: managementUserID
            )
            mergeManagedTokens(tokens, providerID: providerID)
            let remainingManualCount = self.provider(id: providerID)?.manualCompletionRequiredCount ?? 0
            if let refreshedProvider = self.provider(id: providerID) {
                for key in refreshedProvider.keys where key.isEnabled {
                    if key.requestValue(for: .newapi) != nil {
                        await refreshKeyInfo(providerID: providerID, keyID: key.id, managesWorkingState: false)
                    }
                }
            }
            if remainingManualCount > 0 {
                setStatus("已同步 \(tokens.count) 个令牌，\(remainingManualCount) 个需要手动补全", providerID: providerID)
            } else {
                setStatus("已同步 \(tokens.count) 个令牌", providerID: providerID)
            }
        } catch {
            setStatus("同步令牌失败：\(error.localizedDescription)", providerID: providerID)
        }

    }

    private func syncSub2APIManagedTokens(providerID: UUID, provider: ProviderConfig, managesWorkingState: Bool) async {
        guard provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setStatus("请先配置 BaseURL", providerID: providerID)
            return
        }

        guard provider.sub2APIAuthorized else {
            setStatus("请先导入登录态", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在同步 \(provider.name) 的 Keys", providerID: providerID)

        do {
            let session = try await resolveSub2APISession(providerID: providerID, provider: provider)
            let client = Sub2APIClient(baseURLString: provider.baseURL)
            let keys = try await client.fetchManagedKeys(accessToken: session.accessToken)
            mergeSub2APIKeys(keys, providerID: providerID)
            if let refreshedProvider = self.provider(id: providerID) {
                for key in refreshedProvider.keys where key.isEnabled {
                    await refreshKeyInfo(providerID: providerID, keyID: key.id, managesWorkingState: false)
                }
            }
            setStatus("已同步 \(keys.count) 个 Key", providerID: providerID)
        } catch {
            if case Sub2APIClientError.authorizationRequired = error {
                clearSub2APIAuthorization(providerID: providerID)
            }
            setStatus("同步 Key 失败：\(error.localizedDescription)", providerID: providerID)
        }

    }

    private func refreshNewAPIAccountQuota(providerID: UUID, provider: ProviderConfig, managesWorkingState: Bool) async {
        guard let managementToken = provider.managementToken,
              managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setStatus("请先配置系统访问令牌", providerID: providerID)
            return
        }

        guard let managementUserID = provider.managementUserID,
              managementUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setStatus("请先配置用户ID", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
            isWorking = false
            endProviderWork(providerID)
        }
        }
        setStatus("正在读取 \(provider.name) 的账号额度", providerID: providerID)

        do {
            let client = NewAPIClient(baseURLString: provider.baseURL, apiKey: "")
            let accountQuota = try await client.fetchAccountQuota(
                accessToken: managementToken,
                userID: managementUserID
            )
            updateProvider(providerID) { provider in
                provider.accountQuota = accountQuota
            }
            setStatus("账号可用额度 \(accountQuota.availableDescription)", providerID: providerID)
        } catch {
            setStatus("账号额度读取失败：\(error.localizedDescription)", providerID: providerID)
        }

    }

    private func refreshSub2APIAccountQuota(providerID: UUID, provider: ProviderConfig, managesWorkingState: Bool) async {
        guard provider.sub2APIAuthorized else {
            setStatus("请先导入登录态", providerID: providerID)
            return
        }

        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在读取 \(provider.name) 的账号余额", providerID: providerID)

        do {
            let session = try await resolveSub2APISession(providerID: providerID, provider: provider)
            setStatus("账号可用余额 \(session.user.availableDescription)", providerID: providerID)
        } catch {
            if case Sub2APIClientError.authorizationRequired = error {
                clearSub2APIAuthorization(providerID: providerID)
            }
            setStatus("账号余额读取失败：\(error.localizedDescription)", providerID: providerID)
        }

    }

    private func refreshNewAPIQuota(
        providerID: UUID,
        provider: ProviderConfig,
        apiKey: APIKeyConfig,
        managesWorkingState: Bool
    ) async {
        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在读取 \(apiKey.name) 的额度", providerID: providerID)

        do {
            guard let requestValue = apiKey.requestValue(for: .newapi) else {
                throw NewAPIClientError.api("请先手动补全完整 Key")
            }
            let client = NewAPIClient(baseURLString: provider.baseURL, apiKey: requestValue)
            let result = try await client.fetchTokenUsage()
            updateKey(providerID: providerID, keyID: apiKey.id) { key in
                key.lastStatus = .healthy
                key.lastMessage = "可用额度 \(result.usage.availableDescription)"
                key.lastQuota = result.usage
                key.lastCheckedAt = .now
            }
            upsertDailyQuota(providerID: providerID, keyID: apiKey.id, usage: result.usage, rawJSON: result.rawJSON)
            await refreshTodayUsage(providerID: providerID, keyID: apiKey.id, managesWorkingState: false)
            setStatus("额度已更新", providerID: providerID)
        } catch {
            updateKey(providerID: providerID, keyID: apiKey.id) { key in
                key.lastStatus = .failed
                key.lastMessage = error.localizedDescription
                key.lastCheckedAt = .now
            }
            setStatus(error.localizedDescription, providerID: providerID)
        }

    }

    private func refreshSub2APIQuota(
        providerID: UUID,
        provider: ProviderConfig,
        apiKey: APIKeyConfig,
        managesWorkingState: Bool
    ) async {
        if managesWorkingState {
            isWorking = true
            beginProviderWork(providerID)
        }
        defer {
            if managesWorkingState {
                isWorking = false
                endProviderWork(providerID)
            }
        }
        setStatus("正在读取 \(apiKey.name) 的额度", providerID: providerID)

        do {
            let client = Sub2APIClient(baseURLString: provider.baseURL)
            let result = try await client.fetchKeyUsage(apiKey: apiKey.value)
            updateKey(providerID: providerID, keyID: apiKey.id) { key in
                key.lastStatus = keyStatus(for: result.usage, fallbackStatus: key.sub2APIStatus)
                key.lastMessage = result.usage.isValid
                    ? "可用额度 \(result.usage.availableDescription)"
                    : "Key 状态 \(result.usage.status ?? "不可用")"
                key.lastCheckedAt = .now
                key.todayUsedAmountUSD = result.usage.todayUsedAmountUSD
                key.todayUsageCheckedAt = .now
                key.sub2APIUsage = result.usage
                if let quotaLimit = result.usage.quotaLimitUSD {
                    key.sub2APIQuotaLimitUSD = quotaLimit
                }
                if let quotaUsed = result.usage.quotaUsedUSD {
                    key.sub2APIQuotaUsedUSD = quotaUsed
                }
                if let quotaRemaining = result.usage.quotaRemainingUSD ?? result.usage.remaining {
                    key.sub2APIQuotaRemainingUSD = quotaRemaining
                }
                if let status = result.usage.status {
                    key.sub2APIStatus = status
                }
            }
            setStatus("额度已更新", providerID: providerID)
        } catch {
            updateKey(providerID: providerID, keyID: apiKey.id) { key in
                key.lastStatus = .failed
                key.lastMessage = error.localizedDescription
                key.lastCheckedAt = .now
            }
            setStatus(error.localizedDescription, providerID: providerID)
        }

    }

    private func resolveSub2APISession(
        providerID: UUID,
        provider: ProviderConfig,
        forceRefresh: Bool = false
    ) async throws -> Sub2APIAuthorizationSession {
        let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBaseURL.isEmpty == false else {
            throw Sub2APIClientError.invalidBaseURL
        }

        let client = Sub2APIClient(baseURLString: trimmedBaseURL)
        let cachedAccessToken = provider.sub2APIAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cachedRefreshToken = provider.sub2APIRefreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard cachedRefreshToken.isEmpty == false else {
            throw Sub2APIClientError.authorizationRequired
        }

        let needsRefresh = forceRefresh ||
            cachedAccessToken.isEmpty ||
            (provider.sub2APITokenExpiresAt ?? .distantPast) <= Date().addingTimeInterval(120)

        if needsRefresh {
            let tokenPair = try await client.refreshAuth(refreshToken: cachedRefreshToken)
            let user = try await client.fetchCurrentUser(accessToken: tokenPair.accessToken)
            let session = Sub2APIAuthorizationSession(
                accessToken: tokenPair.accessToken,
                refreshToken: tokenPair.refreshToken,
                tokenExpiresAt: tokenPair.tokenExpiresAt,
                user: user
            )
            storeSub2APISession(session, providerID: providerID)
            return session
        }

        do {
            let user = try await client.fetchCurrentUser(accessToken: cachedAccessToken)
            let session = Sub2APIAuthorizationSession(
                accessToken: cachedAccessToken,
                refreshToken: cachedRefreshToken,
                tokenExpiresAt: provider.sub2APITokenExpiresAt,
                user: user
            )
            storeSub2APISession(session, providerID: providerID)
            return session
        } catch {
            if case Sub2APIClientError.authorizationRequired = error {
                return try await resolveSub2APISession(providerID: providerID, provider: provider, forceRefresh: true)
            }
            throw error
        }
    }

    private func storeSub2APISession(_ session: Sub2APIAuthorizationSession, providerID: UUID) {
        updateProvider(providerID) { provider in
            provider.sub2APIAccessToken = session.accessToken
            provider.sub2APIRefreshToken = session.refreshToken
            provider.sub2APITokenExpiresAt = session.tokenExpiresAt
            provider.sub2APIUser = session.user
        }
    }

    private func clearSub2APIAuthorization(providerID: UUID) {
        updateProvider(providerID) { provider in
            provider.sub2APIAccessToken = nil
            provider.sub2APIRefreshToken = nil
            provider.sub2APITokenExpiresAt = nil
            provider.sub2APIUser = nil
        }
    }

    private func upsertModels(providerID: UUID, keyID: UUID, modelIDs: [String]) {
        data.modelRecords.removeAll { $0.providerID == providerID && $0.keyID == keyID }
        data.modelRecords.append(contentsOf: modelIDs.map {
            ModelRecord(providerID: providerID, keyID: keyID, modelID: $0)
        })
        persist()
    }

    private func upsertDailyQuota(providerID: UUID, keyID: UUID, usage: TokenUsage, rawJSON: String) {
        let today = Self.dayString(for: .now)
        if let index = data.quotaRecords.firstIndex(where: {
            $0.providerID == providerID && $0.keyID == keyID && $0.day == today
        }) {
            data.quotaRecords[index].usage = usage
            data.quotaRecords[index].rawJSON = rawJSON
            data.quotaRecords[index].recordedAt = .now
        } else {
            data.quotaRecords.append(QuotaDailyRecord(
                providerID: providerID,
                keyID: keyID,
                day: today,
                usage: usage,
                rawJSON: rawJSON
            ))
        }
        persist()
    }

    private func storeTestResult(_ result: ModelTestResult) {
        data.testResults.append(result)
        data.testResults = Array(data.testResults.sorted { $0.testedAt > $1.testedAt }.prefix(400))

        if let index = data.modelRecords.firstIndex(where: {
            $0.providerID == result.providerID && $0.keyID == result.keyID && $0.modelID == result.modelID
        }) {
            switch result.mode {
            case .stream:
                data.modelRecords[index].streamResult = result
            case .nonStream:
                data.modelRecords[index].nonStreamResult = result
            }
        }
        persist()
    }

    private func mergeManagedTokens(_ tokens: [ManagedToken], providerID: UUID) {
        guard let providerIndex = data.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }

        let existingKeys = data.providers[providerIndex].keys
        var consumedKeyIDs = Set<UUID>()
        var syncedKeys: [APIKeyConfig] = []

        let orderedTokens = tokens.sorted { lhs, rhs in
            if lhs.id != rhs.id {
                return lhs.id < rhs.id
            }

            return (lhs.createdTime ?? 0) < (rhs.createdTime ?? 0)
        }

        for token in orderedTokens {
            var apiKey = existingKeys.first {
                $0.managedTokenID == token.id || $0.value == token.key
            } ?? APIKeyConfig(name: token.name, value: token.key)
            let needsManualCompletion = token.key.contains("*") || token.key.contains("•")

            apiKey.name = token.name
            if needsManualCompletion {
                apiKey.remoteMaskedValue = token.key
                if apiKey.requestValue(for: .newapi) == nil {
                    apiKey.value = token.key
                    apiKey.requiresManualCompletion = true
                    apiKey.lastStatus = .warning
                    apiKey.lastMessage = "请手动补全完整 Key"
                    apiKey.lastQuota = nil
                } else {
                    apiKey.requiresManualCompletion = false
                }
            } else {
                apiKey.value = token.key
                apiKey.remoteMaskedValue = nil
                apiKey.requiresManualCompletion = false
            }
            apiKey.managedTokenID = token.id
            apiKey.managedCreatedTime = token.createdTime
            apiKey.managedRemainQuota = token.remainQuota
            apiKey.managedUsedQuota = token.usedQuota
            apiKey.managedUnlimitedQuota = token.unlimitedQuota
            apiKey.managedStatus = token.status
            apiKey.managedExpiredTime = token.expiredTime
            apiKey.todayUsedQuota = token.todayUsedQuota ?? apiKey.todayUsedQuota
            apiKey.isEnabled = token.status.map { $0 != 0 } ?? apiKey.isEnabled
            apiKey.updatedAt = .now

            consumedKeyIDs.insert(apiKey.id)
            syncedKeys.append(apiKey)
        }

        let localOnlyKeys = existingKeys.filter { consumedKeyIDs.contains($0.id) == false }
        data.providers[providerIndex].keys = syncedKeys + localOnlyKeys
        data.providers[providerIndex].requiresManualKeyCompletion = data.providers[providerIndex].keys.contains(where: \.requiresManualCompletion)
        data.providers[providerIndex].updatedAt = .now
        persist()
    }

    private func mergeSub2APIKeys(_ keys: [Sub2APIManagedKey], providerID: UUID) {
        guard let providerIndex = data.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }

        let existingKeys = data.providers[providerIndex].keys
        var consumedKeyIDs = Set<UUID>()
        var syncedKeys: [APIKeyConfig] = []

        let orderedKeys = keys.sorted { lhs, rhs in
            if lhs.id != rhs.id {
                return lhs.id < rhs.id
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        for managedKey in orderedKeys {
            var apiKey = existingKeys.first {
                $0.remoteID == managedKey.id || $0.value == managedKey.key
            } ?? APIKeyConfig(name: managedKey.name, value: managedKey.key)

            apiKey.name = managedKey.name
            apiKey.value = managedKey.key
            apiKey.remoteID = managedKey.id
            apiKey.sub2APIStatus = managedKey.status
            apiKey.sub2APIQuotaLimitUSD = managedKey.quotaLimitUSD
            apiKey.sub2APIQuotaUsedUSD = managedKey.quotaUsedUSD
            apiKey.sub2APIQuotaRemainingUSD = managedKey.quotaLimitUSD > 0
                ? max(0, managedKey.quotaLimitUSD - managedKey.quotaUsedUSD)
                : apiKey.sub2APIQuotaRemainingUSD
            apiKey.sub2APIExpiresAt = managedKey.expiresAt
            apiKey.isEnabled = managedKey.status != "disabled"
            apiKey.lastStatus = keyStatus(forManagedSub2APIStatus: managedKey.status)
            apiKey.updatedAt = .now

            consumedKeyIDs.insert(apiKey.id)
            syncedKeys.append(apiKey)
        }

        let localOnlyKeys = existingKeys.filter { consumedKeyIDs.contains($0.id) == false }
        data.providers[providerIndex].keys = syncedKeys + localOnlyKeys
        data.providers[providerIndex].updatedAt = .now
        persist()
    }

    private func keyStatus(for usage: Sub2APIUsageSnapshot, fallbackStatus: String?) -> KeyStatus {
        if usage.isValid == false {
            return .warning
        }

        if let status = usage.status ?? fallbackStatus {
            return keyStatus(forManagedSub2APIStatus: status)
        }

        return .healthy
    }

    private func keyStatus(forManagedSub2APIStatus status: String?) -> KeyStatus {
        switch status?.lowercased() {
        case "active":
            return .healthy
        case "quota_exhausted", "expired":
            return .warning
        case "disabled":
            return .disabled
        case .none:
            return .unknown
        default:
            return .warning
        }
    }

    private func persist() {
        data.updatedAt = .now
        do {
            try store.save(data)
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private static func dayString(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
