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
    @State private var cliProxyPanelTab: MenuCLIProxyPanelTab = .codexAccounts

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
        .background(ModelsBarTheme.menuWindowBackground)
        .background(MenuBarWindowConfigurator())
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
                    Text("先在设置里添加站点，并配置系统令牌、登录态，或直接添加 OpenAI 兼容 API Key。")
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
                .overlay(ModelsBarTheme.menuSeparator)
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
        if selectedProvider?.type == .ccSwitch {
            let accounts = selectedProvider?.codexAccounts ?? []
            let healthyCount = accounts.filter { $0.effectiveStatus == .healthy }.count
            return "\(healthyCount)/\(accounts.count) 个 Codex 账号正常"
        }

        return "\(activeProviderHealthyKeyCount)/\(activeProviderEnabledKeyCount) 个 Key 正常"
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
        if selectedProvider?.type == .ccSwitch {
            let accounts = selectedProvider?.codexAccounts ?? []
            if accounts.contains(where: { [.failed, .exhausted, .warning].contains($0.effectiveStatus) }) {
                return "exclamationmark.triangle.fill"
            }
            if accounts.contains(where: { $0.effectiveStatus == .healthy }) {
                return "checkmark.circle.fill"
            }
            return "bolt.fill"
        }

        if activeProviderFailedKeyCount > 0 {
            return "exclamationmark.triangle.fill"
        }

        if activeProviderHealthyKeyCount > 0 {
            return "checkmark.circle.fill"
        }

        return "bolt.fill"
    }

    private var activeProviderTint: Color {
        if selectedProvider?.type == .ccSwitch {
            let accounts = selectedProvider?.codexAccounts ?? []
            return accounts.contains(where: { [.failed, .exhausted, .warning].contains($0.effectiveStatus) }) ? .red : .green
        }

        return activeProviderFailedKeyCount > 0 ? .red : .green
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
                .help(syncButtonHelp(provider))
                .disabled(state.isWorking)
            }

            if provider.type == .cliProxy {
                MenuCLIProxyPanelTabs(selection: $cliProxyPanelTab)
                    .padding(.top, 1)

                switch cliProxyPanelTab {
                case .apiKeys:
                    cliProxyAPIKeyList(provider)

                case .codexAccounts:
                    cliProxyCodexAccountList(provider)
                }
            } else if provider.type == .ccSwitch {
                ccSwitchCodexAccountList(provider)
            } else if provider.keys.isEmpty {
                CompactMenuPanel {
                    Text(emptyKeyMessage(provider))
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

    private func cliProxyAPIKeyList(_ provider: ProviderConfig) -> some View {
        Group {
            if provider.keys.isEmpty {
                CompactMenuPanel {
                    Text(emptyKeyMessage(provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if needsScrollableKeyList(provider) {
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

    private func cliProxyCodexAccountList(_ provider: ProviderConfig) -> some View {
        codexAccountList(
            provider,
            emptyMessage: "点击同步后会读取 CLI Proxy API 管理端里的 Codex 认证账号。"
        )
    }

    private func ccSwitchCodexAccountList(_ provider: ProviderConfig) -> some View {
        codexAccountList(
            provider,
            emptyMessage: "点击同步后会读取 CC Switch 本地数据库里的 Codex official 账号。"
        )
    }

    private func codexAccountList(_ provider: ProviderConfig, emptyMessage: String) -> some View {
        Group {
            if provider.codexAccounts.isEmpty {
                CompactMenuPanel {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if needsScrollableCodexAccountList(provider) {
                ScrollView(.vertical, showsIndicators: false) {
                    codexAccountCards(provider)
                        .padding(.trailing, 4)
                }
                .frame(maxHeight: maxKeyListHeight, alignment: .top)
            } else {
                codexAccountCards(provider)
            }
        }
    }

    private func needsScrollableKeyList(_ provider: ProviderConfig) -> Bool {
        let keyCardHeight: CGFloat = provider.type == .cliProxy ? 86 : 104
        let keyCardSpacing: CGFloat = 8
        let listHeight = CGFloat(provider.keys.count) * keyCardHeight
            + CGFloat(max(provider.keys.count - 1, 0)) * keyCardSpacing
        return listHeight > maxKeyListHeight
    }

    private func needsScrollableCodexAccountList(_ provider: ProviderConfig) -> Bool {
        let accountCardHeight: CGFloat = 124
        let accountCardSpacing: CGFloat = 8
        let listHeight = CGFloat(provider.codexAccounts.count) * accountCardHeight
            + CGFloat(max(provider.codexAccounts.count - 1, 0)) * accountCardSpacing
        return listHeight > maxKeyListHeight
    }

    private func emptyKeyMessage(_ provider: ProviderConfig) -> String {
        switch provider.type {
        case .newapi:
            return "这个站点下还没有 Key。"
        case .cliProxy:
            return "点击同步后会拉取 CLI Proxy API 管理端里的全部 API Keys。"
        case .ccSwitch:
            return "点击同步后会读取 CC Switch 本地数据库里的 Codex official 账号。"
        case .openAICompatible:
            return "先到设置里手动添加 API Key，再点击刷新模型。"
        case .sub2api:
            return provider.sub2APIAuthorized ? "点击同步后会拉取账号下的全部 Key。" : "先到设置里导入 Sub2API 登录态。"
        }
    }

    private func syncButtonHelp(_ provider: ProviderConfig) -> String {
        switch provider.type {
        case .newapi:
            return "同步当前站点的账号额度、Keys、Key 额度和可用模型"
        case .cliProxy:
            return "同步 CLI Proxy API 管理端中的 API Keys，并刷新模型"
        case .ccSwitch:
            return "读取 CC Switch 本地数据库中的 Codex official 账号，并刷新额度"
        case .openAICompatible:
            return "刷新当前站点下全部手动维护 Key 的模型列表"
        case .sub2api:
            return "同步当前站点的账号余额、Keys、Key 额度和可用模型"
        }
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

    private func codexAccountCards(_ provider: ProviderConfig) -> some View {
        VStack(spacing: 8) {
            ForEach(provider.codexAccounts, id: \.fileName) { account in
                MenuCodexAccountCard(providerID: provider.id, account: account)
            }
        }
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

private struct MenuBarWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView)
        }
    }

    private func configureWindow(from view: NSView) {
        guard let window = view.window else {
            return
        }

        window.backgroundColor = ModelsBarTheme.nsMenuWindowBackground
        window.isOpaque = false
    }
}

private enum MenuCLIProxyPanelTab: String, CaseIterable, Identifiable {
    case codexAccounts
    case apiKeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiKeys:
            return "API Key"
        case .codexAccounts:
            return "Codex 账号"
        }
    }
}

private struct MenuCLIProxyPanelTabs: View {
    @Binding var selection: MenuCLIProxyPanelTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MenuCLIProxyPanelTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == tab ? ModelsBarTheme.menuSurfaceStrong : ModelsBarTheme.menuSurface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
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
                    if provider.type == .cliProxy {
                        Button {
                            Task { await state.refreshKeyInfo(providerID: provider.id, keyID: apiKey.id) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(canOperateWithKey ? "刷新额度和模型" : "请先到设置里补全完整 Key")
                        .disabled(canOperateWithKey == false || state.isWorking || apiKey.isEnabled == false)
                    } else {
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
                }

                quotaProgress

                if provider.type != .cliProxy {
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

            MenuQuotaProgressBar(value: quotaProgressValue, tint: quotaProgressTint)
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
        let summary = apiKey.quotaSummary(for: provider.type)
        if summary == "--" {
            return .secondary
        }

        if summary == "无限额度" {
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
        if provider.type != .newapi {
            return apiKey.todayUsageDescription(for: provider.type)
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

private struct MenuCodexAccountCard: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var isRefreshing = false

    let providerID: UUID
    let account: CodexAccountSnapshot

    var body: some View {
        CompactMenuPanel {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(account.email)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(account.displayPlanType)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(ModelsBarTheme.pillBackground, in: Capsule())
                        }

                        if let accountID = account.shortAccountID {
                            Text(accountID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Button {
                            isRefreshing = true
                            Task {
                                await state.refreshCodexAccount(providerID: providerID, fileName: account.fileName)
                                await MainActor.run {
                                    isRefreshing = false
                                }
                            }
                        } label: {
                            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isRefreshing ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("刷新此账号额度")
                        .disabled(isRefreshing)

                        StatusBadge(status: account.effectiveStatus)
                    }
                }

                MenuCodexQuotaLine(title: "5h额度", quota: account.fiveHourQuota, tint: .mint)
                MenuCodexQuotaLine(title: "周额度", quota: account.weeklyQuota, tint: .purple)
            }
        }
    }
}

private struct MenuCodexQuotaLine: View {
    let title: String
    let quota: CodexQuotaSnapshot?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(summaryText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            MenuQuotaProgressBar(
                value: quota?.progressValue ?? 0,
                tint: quota?.isDangerouslyLow == true ? Color.red : tint
            )
        }
    }

    private var summaryText: String {
        guard let quota else {
            return "--"
        }

        let percent = "剩余 \(quota.summaryDescription)"
        guard let resetsAt = quota.resetsAt else {
            return percent
        }

        let dateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(resetsAt) ? .omitted : .abbreviated
        return "\(percent) · \(resetsAt.formatted(date: dateStyle, time: .shortened))"
    }
}

private extension CodexQuotaSnapshot {
    var isDangerouslyLow: Bool {
        switch progressTintKind {
        case .danger:
            return true
        case .unknown, .healthy, .warning:
            return false
        }
    }
}

private struct MenuQuotaProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ModelsBarTheme.progressTrack)

                Capsule()
                    .fill(tint.opacity(0.88))
                    .frame(width: max(8, proxy.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: 6)
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
                    .fill(isSelected ? Color.accentColor.opacity(0.92) : ModelsBarTheme.menuSurface))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.7) : ModelsBarTheme.menuBorderSoft)
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
        .background(ModelsBarTheme.menuSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ModelsBarTheme.menuBorder)
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
                        .fill(isHovered ? ModelsBarTheme.menuHover : .clear)
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
            .background(ModelsBarTheme.menuWindowBackground)
        }
    }

    private var records: [ModelRecord] {
        state.modelRecords(providerID: provider.id, keyID: apiKey.id)
    }

    private var modelRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(records) { record in
                MenuBarModelStatusRow(provider: provider, apiKey: apiKey, record: record)
            }
        }
    }
}

private struct MenuBarModelStatusRow: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var selectedInterface: OpenAIModelInterface
    private let interfacePickerWidth: CGFloat = 112

    let provider: ProviderConfig
    let apiKey: APIKeyConfig
    let record: ModelRecord

    init(provider: ProviderConfig, apiKey: APIKeyConfig, record: ModelRecord) {
        self.provider = provider
        self.apiKey = apiKey
        self.record = record
        _selectedInterface = State(initialValue: OpenAIModelInterface.recommended(for: record.modelID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: modelSymbol)
                    .foregroundStyle(modelTint)
                    .frame(width: 16)

                Text(record.modelID)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                if availableInterfaces.count > 1 {
                    interfaceMenu
                }
            }

            HStack(spacing: 6) {
                statusPill(currentResult(for: .nonStream), prefix: "非流式")
                if supportsStreamTesting {
                    statusPill(currentResult(for: .stream), prefix: "流式")
                } else {
                    unsupportedStatusPill(prefix: "流式")
                }

                Spacer()

                Button(buttonTitle(mode: .nonStream)) {
                    state.enqueueModelTest(
                        providerID: provider.id,
                        keyID: apiKey.id,
                        modelID: record.modelID,
                        mode: .nonStream,
                        interface: selectedInterface
                    )
                }
                .lineLimit(1)
                .disabled(buttonDisabled(mode: .nonStream))

                Button(buttonTitle(mode: .stream)) {
                    state.enqueueModelTest(
                        providerID: provider.id,
                        keyID: apiKey.id,
                        modelID: record.modelID,
                        mode: .stream,
                        interface: selectedInterface
                    )
                }
                .lineLimit(1)
                .disabled(buttonDisabled(mode: .stream))
                .help(supportsStreamTesting ? "测试流式响应" : "\(selectedInterface.shortTitle) 不支持流式测试")
            }

            Text(selectedInterface.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(ModelsBarTheme.menuSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var availableInterfaces: [OpenAIModelInterface] {
        OpenAIModelInterface.availableInterfaces(for: record.modelID)
    }

    private var interfaceMenu: some View {
        Menu {
            ForEach(availableInterfaces, id: \.self) { interface in
                Button {
                    selectedInterface = interface
                } label: {
                    if interface == selectedInterface {
                        Label(interface.shortTitle, systemImage: "checkmark")
                    } else {
                        Text(interface.shortTitle)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedInterface.shortTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: interfacePickerWidth, alignment: .leading)
            .background(ModelsBarTheme.menuSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var supportsStreamTesting: Bool {
        selectedInterface.supportsStreamTesting
    }

    private func currentResult(for mode: TestMode) -> ModelTestResult? {
        state.latestModelTestResult(
            providerID: provider.id,
            keyID: apiKey.id,
            modelID: record.modelID,
            mode: mode,
            interface: selectedInterface
        )
    }

    private var aggregateState: ModelAggregateVisualState {
        if supportsStreamTesting == false {
            guard let result = currentResult(for: .nonStream) else {
                return .idle
            }
            return result.succeeded ? .success : .failure
        }

        guard let nonStreamResult = currentResult(for: .nonStream),
              let streamResult = currentResult(for: .stream) else {
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

    private var modelSymbol: String {
        switch aggregateState {
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

    private var modelTint: Color {
        switch aggregateState {
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

    private func executionState(mode: TestMode) -> ModelTestExecutionState {
        state.modelTestExecutionState(
            providerID: provider.id,
            keyID: apiKey.id,
            modelID: record.modelID,
            mode: mode,
            interface: selectedInterface
        )
    }

    private func buttonTitle(mode: TestMode) -> String {
        switch executionState(mode: mode) {
        case .idle:
            return mode == .nonStream ? "非流式" : "流式"
        case .queued:
            return "排队中"
        case .running:
            return "测试中"
        }
    }

    private func buttonDisabled(mode: TestMode) -> Bool {
        if mode == .stream && supportsStreamTesting == false {
            return true
        }

        switch executionState(mode: mode) {
        case .idle:
            return false
        case .queued, .running:
            return true
        }
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
