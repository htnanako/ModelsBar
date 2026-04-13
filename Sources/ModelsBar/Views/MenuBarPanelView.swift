import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var state: ModelsBarState
    @State private var localSelectedProviderID: UUID?
    @State private var providerFrames: [UUID: CGRect] = [:]
    @State private var keyFrames: [UUID: CGRect] = [:]
    @State private var draggedProviderID: UUID?
    @State private var draggedKeyID: UUID?

    private static let coordinateSpaceName = "MenuBarPanelReorderSpace"
    private let providerTabSpacing: CGFloat = 6

    private var maxWindowHeight: CGFloat {
        let screenHeight = NSScreen.main?.frame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        return min(max(screenHeight - 8, 360), 1_320)
    }

    private var maxKeyListHeight: CGFloat {
        max(160, maxWindowHeight - 194)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerSwitcher
            statusLine
            selectedProviderContent
                .layoutPriority(1)
            footer
        }
        .padding(12)
        .frame(width: 440)
        .frame(maxHeight: maxWindowHeight, alignment: .top)
        .background(.ultraThinMaterial)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .onAppear {
            if localSelectedProviderID == nil {
                localSelectedProviderID = state.selectedProviderID ?? state.data.providers.first?.id
            }
        }
        .onChange(of: state.data.providers) { _, providers in
            guard let selected = localSelectedProviderID else {
                localSelectedProviderID = providers.first?.id
                return
            }

            if providers.contains(where: { $0.id == selected }) == false {
                localSelectedProviderID = providers.first?.id
            }
        }
    }

    private var providerSwitcher: some View {
        Group {
            if state.data.providers.isEmpty {
                Text("ModelsBar")
                    .font(.headline)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: providerTabSpacing) {
                            ForEach(state.data.providers) { provider in
                                ProviderSwitchButton(
                                    title: provider.name,
                                    isSelected: provider.id == selectedProvider?.id,
                                    minimumWidth: providerTabMinimumWidth(availableWidth: proxy.size.width),
                                    fillsWidth: shouldFillProviderTabWidth
                                ) {
                                    localSelectedProviderID = provider.id
                                    state.selectedProviderID = provider.id
                                }
                                .opacity(draggedProviderID == provider.id ? 0.72 : 1)
                                .background(providerFrameReader(provider.id))
                                .simultaneousGesture(providerReorderGesture(provider.id))
                            }
                        }
                        .frame(minWidth: proxy.size.width, alignment: .leading)
                        .padding(.vertical, 1)
                    }
                }
                .frame(height: 30)
                .onPreferenceChange(ProviderFramePreferenceKey.self) { providerFrames = $0 }
            }
        }
    }

    private func providerTabMinimumWidth(availableWidth: CGFloat) -> CGFloat? {
        let count = state.data.providers.count
        guard count > 0, count <= 4 else {
            return nil
        }

        let totalSpacing = CGFloat(max(count - 1, 0)) * providerTabSpacing
        return max((availableWidth - totalSpacing) / CGFloat(count), 74)
    }

    private var shouldFillProviderTabWidth: Bool {
        state.data.providers.count <= 4
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: activeProviderSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activeProviderTint)

            Text(activeProviderSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Label(activeProviderQuotaPairDescription, systemImage: "creditcard")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var selectedProviderContent: some View {
        Group {
            if state.data.providers.isEmpty {
                CompactMenuPanel {
                    Text("先在设置里添加站点并配置系统令牌或 Sub2API 登录态。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let provider = selectedProvider {
                providerKeyList(provider)
            } else {
                EmptyView()
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.bottom, 4)

            MenuCommandRow(title: "Settings") {
                closeMenuBarWindowAndOpenSettings()
            }
            .menuShortcutLabel("⌘,")
            .keyboardShortcut(",", modifiers: .command)

            MenuCommandRow(title: "About ModelsBar") {
                closeMenuBarWindowAndOpenAbout()
            }

            MenuCommandRow(title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func closeMenuBarWindowAndOpenSettings() {
        NSApplication.shared.keyWindow?.close()
        DispatchQueue.main.async {
            openSettings()
            bringSettingsWindowToFront()
        }
    }

    private func closeMenuBarWindowAndOpenAbout() {
        NSApplication.shared.keyWindow?.close()
        DispatchQueue.main.async {
            openWindow(id: modelsBarAboutWindowID)
            bringAboutWindowToFront()
        }
    }

    private func bringSettingsWindowToFront(attempt: Int = 0) {
        if let window = NSApplication.shared.windows.first(where: { $0.identifier == modelsBarSettingsWindowIdentifier }) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        guard attempt < 8 else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            bringSettingsWindowToFront(attempt: attempt + 1)
        }
    }

    private func bringAboutWindowToFront(attempt: Int = 0) {
        if let window = NSApplication.shared.windows.first(where: { $0.identifier == modelsBarAboutWindowIdentifier }) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        guard attempt < 8 else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            bringAboutWindowToFront(attempt: attempt + 1)
        }
    }

    private var selectedProvider: ProviderConfig? {
        if let localSelectedProviderID,
           let provider = state.provider(id: localSelectedProviderID) {
            return provider
        }

        return state.data.providers.first
    }

    private var activeProviderKeys: [APIKeyConfig] {
        selectedProvider?.keys ?? []
    }

    private var activeProviderEnabledKeyCount: Int {
        activeProviderKeys.filter(\.isEnabled).count
    }

    private var activeProviderHealthyKeyCount: Int {
        activeProviderKeys.filter { $0.lastStatus == .healthy }.count
    }

    private var activeProviderFailedKeyCount: Int {
        activeProviderKeys.filter { $0.lastStatus == .failed }.count
    }

    private var activeProviderSummaryText: String {
        "\(activeProviderHealthyKeyCount)/\(activeProviderEnabledKeyCount) 个 Key 正常"
    }

    private var activeProviderQuotaPairDescription: String {
        "\(activeProviderTodayUsageDescription) / \(activeProviderAccountQuotaDescription)"
    }

    private var activeProviderTodayUsageDescription: String {
        selectedProvider?.totalTodayUsageDescription ?? "--"
    }

    private var activeProviderAccountQuotaDescription: String {
        selectedProvider?.accountAvailableDescription ?? "--"
    }

    private var activeProviderSymbol: String {
        if activeProviderFailedKeyCount > 0 {
            return "exclamationmark.triangle.fill"
        }

        if activeProviderHealthyKeyCount > 0 {
            return "checkmark.circle.fill"
        }

        return "bolt.fill"
    }

    private var activeProviderTint: Color {
        activeProviderFailedKeyCount > 0 ? .red : .green
    }

    private func providerKeyList(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(provider.displayBaseURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await state.syncManagedTokens(providerID: provider.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("同步当前站点的账号额度、Keys、Key 额度和可用模型")
                .disabled(state.isWorking)
            }

            if provider.keys.isEmpty {
                CompactMenuPanel {
                    Text(provider.type == .newapi ? "这个站点下还没有 Key。" : (provider.sub2APIAuthorized ? "点击同步后会拉取账号下的全部 Key。" : "先到设置里导入 Sub2API 登录态。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                if needsScrollableKeyList(provider) {
                    ScrollView(.vertical, showsIndicators: false) {
                        keyCards(provider)
                            .padding(.trailing, 4)
                    }
                    .frame(maxHeight: maxKeyListHeight, alignment: .top)
                } else {
                    keyCards(provider)
                }
            }
        }
    }

    private func needsScrollableKeyList(_ provider: ProviderConfig) -> Bool {
        let keyCardHeight: CGFloat = 104
        let keyCardSpacing: CGFloat = 8
        let listHeight = CGFloat(provider.keys.count) * keyCardHeight
            + CGFloat(max(provider.keys.count - 1, 0)) * keyCardSpacing
        return listHeight > maxKeyListHeight
    }

    private func keyCards(_ provider: ProviderConfig) -> some View {
        VStack(spacing: 8) {
            ForEach(provider.keys) { apiKey in
                KeyOverviewCard(provider: provider, apiKey: apiKey)
                    .opacity(draggedKeyID == apiKey.id ? 0.72 : 1)
                    .background(keyFrameReader(apiKey.id))
                    .simultaneousGesture(keyReorderGesture(providerID: provider.id, keyID: apiKey.id))
            }
        }
        .onPreferenceChange(KeyFramePreferenceKey.self) { keyFrames = $0 }
    }

    private func providerFrameReader(_ providerID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ProviderFramePreferenceKey.self,
                value: [providerID: proxy.frame(in: .named(Self.coordinateSpaceName))]
            )
        }
    }

    private func keyFrameReader(_ keyID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: KeyFramePreferenceKey.self,
                value: [keyID: proxy.frame(in: .named(Self.coordinateSpaceName))]
            )
        }
    }

    private func providerReorderGesture(_ providerID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                draggedProviderID = providerID
                let orderedFrames = state.data.providers.compactMap { provider -> CGRect? in
                    providerFrames[provider.id]
                }
                let destination = horizontalInsertionIndex(for: value.location.x, frames: orderedFrames)
                state.moveProvider(providerID, toIndex: destination)
            }
            .onEnded { _ in
                draggedProviderID = nil
            }
    }

    private func keyReorderGesture(providerID: UUID, keyID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                draggedKeyID = keyID
                let orderedFrames = state.provider(id: providerID)?.keys.compactMap { key -> CGRect? in
                    keyFrames[key.id]
                } ?? []
                let destination = verticalInsertionIndex(for: value.location.y, frames: orderedFrames)
                state.moveKey(providerID: providerID, keyID: keyID, toIndex: destination)
            }
            .onEnded { _ in
                draggedKeyID = nil
            }
    }

    private func horizontalInsertionIndex(for xPosition: CGFloat, frames: [CGRect]) -> Int {
        frames.firstIndex { xPosition < $0.midX } ?? frames.count
    }

    private func verticalInsertionIndex(for yPosition: CGFloat, frames: [CGRect]) -> Int {
        frames.firstIndex { yPosition < $0.midY } ?? frames.count
    }
}

private struct ProviderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct KeyFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct KeyOverviewCard: View {
    @EnvironmentObject private var state: ModelsBarState
    let provider: ProviderConfig
    let apiKey: APIKeyConfig

    var body: some View {
        CompactMenuPanel {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(apiKey.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(apiKey.maskedValue(for: provider.type))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if needsManualCompletion {
                            Text("需到设置中补全")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }

                    Spacer()

                    StatusBadge(status: apiKey.isEnabled ? apiKey.lastStatus : .disabled)
                    Button {
                        copyAPIKey()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help(canCopyAPIKey ? "复制 Key" : "请先到设置里补全完整 Key")
                    .disabled(canCopyAPIKey == false)
                    ModelsStatusMenu(provider: provider, apiKey: apiKey)
                        .disabled(canOperateWithKey == false)
                }

                quotaProgress

                HStack(spacing: 8) {
                    metricText(
                        title: "今日",
                        value: todayUsageDescription,
                        systemImage: "calendar"
                    )

                    Spacer()

                    Button {
                        Task { await state.refreshKeyInfo(providerID: provider.id, keyID: apiKey.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(canOperateWithKey ? "刷新额度和模型" : "请先到设置里补全完整 Key")
                    .disabled(canOperateWithKey == false)
                }
                .disabled(state.isWorking || apiKey.isEnabled == false)
            }
        }
    }

    private var quotaProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .foregroundStyle(.secondary)
                Text("Key 额度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(quotaProgressTitle)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }

            ProgressView(value: quotaProgressValue)
                .progressViewStyle(.linear)
                .tint(quotaProgressTint)
        }
    }

    private var quotaProgressTitle: String {
        let summary = apiKey.quotaSummary(for: provider.type)
        if summary == "无限额度" {
            return "无限额度"
        }
        return summary
    }

    private var quotaProgressValue: Double {
        apiKey.quotaProgress(for: provider.type)
    }

    private var quotaProgressTint: Color {
        if apiKey.quotaSummary(for: provider.type) == "无限额度" {
            return .green
        }

        switch quotaProgressValue {
        case 0..<0.15:
            return .red
        case 0..<0.35:
            return .yellow
        default:
            return .green
        }
    }

    private var todayUsageDescription: String {
        if provider.type == .sub2api {
            return apiKey.todayUsageDescription(for: .sub2api)
        }

        if let todayUsedQuota = apiKey.todayUsedQuota {
            return todayUsedQuota.newAPIQuotaDollarDescription
        }

        let records = state.quotaRecords(providerID: provider.id, keyID: apiKey.id)
        let today = Calendar.current.startOfDay(for: .now)
        let todayRecord = records.first { Calendar.current.isDate($0.recordedAt, inSameDayAs: today) }

        guard let usage = todayRecord?.usage ?? apiKey.lastQuota else {
            return "--"
        }

        let previous = records
            .filter { Calendar.current.startOfDay(for: $0.recordedAt) < today }
            .sorted { $0.recordedAt > $1.recordedAt }
            .first

        if let previous {
            return max(0, usage.totalUsed - previous.usage.totalUsed).newAPIQuotaDollarDescription
        }

        return "--"
    }

    private func metricText(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
    }

    private func copyAPIKey() {
        guard canCopyAPIKey else {
            state.statusMessage = "\(apiKey.name) 需要先在设置里补全 Key"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyableAPIKey, forType: .string)
        state.statusMessage = "已复制 \(apiKey.name)"
    }

    private var copyableAPIKey: String {
        apiKey.displayValue(for: provider.type)
    }

    private var canOperateWithKey: Bool {
        provider.type != .newapi || apiKey.requestValue(for: .newapi) != nil
    }

    private var canCopyAPIKey: Bool {
        canOperateWithKey
    }

    private var needsManualCompletion: Bool {
        provider.type == .newapi && canOperateWithKey == false
    }
}

private struct ProviderSwitchButton: View {
    let title: String
    let isSelected: Bool
    var minimumWidth: CGFloat? = nil
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : .primary)
                .fixedSize(horizontal: fillsWidth == false, vertical: false)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.06)))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08))
                }
        }
        .frame(minWidth: minimumWidth)
        .buttonStyle(.plain)
    }
}

private struct CompactMenuPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.14))
        }
    }
}

private struct MenuCommandRow: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    private var shortcutLabel: String?

    init(title: String, shortcutLabel: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcutLabel = shortcutLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let shortcutLabel {
                    Text(shortcutLabel)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Color.white.opacity(0.10) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
    }

    func menuShortcutLabel(_ label: String?) -> Self {
        var copy = self
        copy.shortcutLabel = label
        return copy
    }
}

private struct ModelsStatusMenu: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var isPresented = false
    let provider: ProviderConfig
    let apiKey: APIKeyConfig

    private var maxModelListHeight: CGFloat {
        min((NSScreen.main?.visibleFrame.height ?? 900) * 0.78, 820)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Models \(records.count)", systemImage: "cube.transparent")
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("模型状态")
                        .font(.headline)

                    Spacer()

                    let providerStatus = state.providerStatusMessage(for: provider.id)
                    if state.isProviderWorking(provider.id) || providerStatus != "就绪" {
                        Text(providerStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if state.isProviderWorking(provider.id) {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Button {
                    Task { await state.refreshKeyInfo(providerID: provider.id, keyID: apiKey.id) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .lineLimit(1)
                }
                .disabled(state.isWorking || apiKey.isEnabled == false)

                Divider()

                if records.isEmpty {
                    Label("还没有模型", systemImage: "cube.transparent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else if records.count <= 14 {
                    modelRows
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        modelRows
                        .padding(.trailing, 4)
                    }
                    .frame(maxHeight: maxModelListHeight)
                }
            }
            .padding(12)
            .frame(width: 500)
            .background(.regularMaterial)
        }
    }

    private var records: [ModelRecord] {
        state.modelRecords(providerID: provider.id, keyID: apiKey.id)
    }

    private var modelRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(records) { record in
                modelRow(record)
            }
        }
    }

    private func modelRow(_ record: ModelRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: modelSymbol(record))
                    .foregroundStyle(modelTint(record))
                    .frame(width: 16)

                Text(record.modelID)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                statusPill(record.nonStreamResult, prefix: "非流式")
                if supportsStreamTesting(record) {
                    statusPill(record.streamResult, prefix: "流式")
                } else {
                    unsupportedStatusPill(prefix: "流式")
                }

                Spacer()

                Button(buttonTitle(record, mode: .nonStream)) {
                    state.enqueueModelTest(
                        providerID: provider.id,
                        keyID: apiKey.id,
                        modelID: record.modelID,
                        mode: .nonStream
                    )
                }
                .lineLimit(1)
                .disabled(buttonDisabled(record, mode: .nonStream))

                Button(buttonTitle(record, mode: .stream)) {
                    state.enqueueModelTest(
                        providerID: provider.id,
                        keyID: apiKey.id,
                        modelID: record.modelID,
                        mode: .stream
                    )
                }
                .lineLimit(1)
                .disabled(buttonDisabled(record, mode: .stream))
                .help(supportsStreamTesting(record) ? "测试流式响应" : "Embedding 接口不支持流式测试")
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusPill(_ result: ModelTestResult?, prefix: String) -> some View {
        Label(statusTitle(result, prefix: prefix), systemImage: statusSymbol(result))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusTint(result))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusTint(result).opacity(0.12), in: Capsule())
    }

    private func unsupportedStatusPill(prefix: String) -> some View {
        Label("\(prefix)：不支持", systemImage: "nosign")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func modelSymbol(_ record: ModelRecord) -> String {
        switch aggregateState(record) {
        case .success:
            return "checkmark.circle.fill"
        case .mixed:
            return "exclamationmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .idle:
            return "minus.circle"
        }
    }

    private func modelTint(_ record: ModelRecord) -> Color {
        switch aggregateState(record) {
        case .success:
            return .green
        case .mixed:
            return .yellow
        case .failure:
            return .red
        case .idle:
            return .secondary
        }
    }

    private func supportsStreamTesting(_ record: ModelRecord) -> Bool {
        OpenAIModelInterface(modelID: record.modelID).supportsStreamTesting
    }

    private func statusResults(_ record: ModelRecord) -> [ModelTestResult] {
        supportsStreamTesting(record)
            ? [record.nonStreamResult, record.streamResult].compactMap(\.self)
            : [record.nonStreamResult].compactMap(\.self)
    }

    private func expectedStatusResultCount(_ record: ModelRecord) -> Int {
        supportsStreamTesting(record) ? 2 : 1
    }

    private func aggregateState(_ record: ModelRecord) -> ModelAggregateVisualState {
        if supportsStreamTesting(record) == false {
            guard let result = record.nonStreamResult else {
                return .idle
            }
            return result.succeeded ? .success : .failure
        }

        guard let nonStreamResult = record.nonStreamResult,
              let streamResult = record.streamResult else {
            return .idle
        }

        if nonStreamResult.succeeded && streamResult.succeeded {
            return .success
        }

        if nonStreamResult.succeeded != streamResult.succeeded {
            return .mixed
        }

        return .failure
    }

    private func executionState(_ record: ModelRecord, mode: TestMode) -> ModelTestExecutionState {
        state.modelTestExecutionState(
            providerID: provider.id,
            keyID: apiKey.id,
            modelID: record.modelID,
            mode: mode
        )
    }

    private func buttonTitle(_ record: ModelRecord, mode: TestMode) -> String {
        switch executionState(record, mode: mode) {
        case .idle:
            return mode == .nonStream ? "非流式" : "流式"
        case .queued:
            return "排队中"
        case .running:
            return "测试中"
        }
    }

    private func buttonDisabled(_ record: ModelRecord, mode: TestMode) -> Bool {
        if mode == .stream && supportsStreamTesting(record) == false {
            return true
        }

        switch executionState(record, mode: mode) {
        case .idle:
            return false
        case .queued, .running:
            return true
        }
    }

    private func statusSymbol(_ result: ModelTestResult?) -> String {
        guard let result else {
            return "minus.circle"
        }

        return result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func statusTint(_ result: ModelTestResult?) -> Color {
        guard let result else {
            return .secondary
        }

        return result.succeeded ? .green : .red
    }

    private func statusTitle(_ result: ModelTestResult?, prefix: String) -> String {
        guard let result else {
            return "\(prefix)：未测试"
        }

        if result.succeeded {
            return "\(prefix)：\(result.latencyMS)ms"
        }

        return "\(prefix)：失败"
    }
}
