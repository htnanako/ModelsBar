import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var addProviderSheetType: ProviderType?
    @State private var providerFrames: [UUID: CGRect] = [:]
    @State private var draggedProviderID: UUID?

    private static let coordinateSpaceName = "SettingsSidebarReorderSpace"

    var body: some View {
        ZStack {
            SettingsWindowBackground()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 304)

                Rectangle()
                    .fill(ModelsBarTheme.separator)
                    .frame(width: 1)

                Group {
                    if let providerID = state.selectedProviderID,
                       state.provider(id: providerID) != nil {
                        ProviderDetailView(providerID: providerID)
                    } else {
                        SettingsWelcomeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .background(SettingsWindowConfigurator())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .coordinateSpace(name: Self.coordinateSpaceName)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            sidebarHeader

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if state.data.providers.isEmpty {
                        CompactEmptyRow(title: "还没有站点", systemImage: "server.rack")
                            .padding(.top, 12)
                    } else {
                        ForEach(state.data.providers) { provider in
                            ProviderSidebarCard(
                                provider: provider,
                                isSelected: state.selectedProviderID == provider.id
                            ) {
                                state.selectedProviderID = provider.id
                            }
                            .opacity(draggedProviderID == provider.id ? 0.72 : 1)
                            .background(providerFrameReader(provider.id))
                            .simultaneousGesture(providerReorderGesture(provider.id))
                        }
                    }
                }
                .padding(.vertical, 2)
                .onPreferenceChange(SettingsProviderFramePreferenceKey.self) { providerFrames = $0 }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ModelsBarTheme.settingsSidebarBackground)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("站点")
                        .font(.title3.weight(.semibold))
                    Text("管理同步站点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HeaderSymbolButton(systemImage: "arrow.clockwise") {
                    Task { await state.syncAllManagedTokens() }
                }
                .help("刷新全部站点")
                .disabled(state.isWorking || state.syncableProviderCount == 0)

                Menu {
                    ForEach(ProviderType.allCases) { type in
                        Button(type.title) {
                            addProviderSheetType = type
                        }
                    }
                } label: {
                    HeaderSymbolLabel(systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("添加站点")
                .sheet(item: $addProviderSheetType) { providerType in
                    AddProviderSheet(providerType: providerType)
                        .environmentObject(state)
                }
            }

            HStack(spacing: 8) {
                SidebarHeaderMetric(
                    title: "站点",
                    value: "\(state.data.providers.count)",
                    systemImage: "server.rack",
                    tint: .blue
                )

                SidebarHeaderMetric(
                    title: "正常",
                    value: "\(state.healthyKeyCount)",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }

            Rectangle()
                .fill(ModelsBarTheme.separator)
                .frame(height: 1)
        }
    }

    private func providerFrameReader(_ providerID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SettingsProviderFramePreferenceKey.self,
                value: [providerID: proxy.frame(in: .named(Self.coordinateSpaceName))]
            )
        }
    }

    private func providerReorderGesture(_ providerID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                draggedProviderID = providerID
                let orderedFrames = state.data.providers.compactMap { provider in
                    providerFrames[provider.id]
                }
                let destination = verticalInsertionIndex(for: value.location.y, frames: orderedFrames)
                state.moveProvider(providerID, toIndex: destination)
            }
            .onEnded { _ in
                draggedProviderID = nil
            }
    }

    private func verticalInsertionIndex(for yPosition: CGFloat, frames: [CGRect]) -> Int {
        frames.firstIndex { yPosition < $0.midY } ?? frames.count
    }
}

private struct SettingsProviderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ProviderSidebarCard: View {
    let provider: ProviderConfig
    let isSelected: Bool
    let action: () -> Void

    private var backgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.94) : ModelsBarTheme.menuSurface
    }

    private var borderColor: Color {
        isSelected ? Color.white.opacity(0.16) : ModelsBarTheme.menuBorderSoft
    }

    private var titleColor: Color {
        isSelected ? .white : .primary
    }

    private var secondaryColor: Color {
        isSelected ? .white.opacity(0.82) : .secondary
    }

    private var tertiaryColor: Color {
        isSelected ? .white.opacity(0.76) : .secondary.opacity(0.75)
    }

    private var iconColor: Color {
        isSelected ? .white.opacity(0.92) : .secondary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(provider.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    Text(provider.type.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color.white.opacity(0.14) : ModelsBarTheme.pillBackground, in: Capsule())

                    Spacer(minLength: 0)

                    if provider.keys.isEmpty == false {
                        Text("\(provider.keys.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.white.opacity(0.14) : ModelsBarTheme.pillBackground, in: Capsule())
                    }
                }

                Text(provider.displayBaseURL)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(provider.keys.filter(\.isEnabled).count) 个 Key", systemImage: "key.horizontal")
                    Label("\(todayUsageDescription) / \(accountQuotaDescription)", systemImage: "creditcard")
                }
                .font(.caption2)
                .foregroundStyle(tertiaryColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var todayUsageDescription: String {
        provider.totalTodayUsageDescription
    }

    private var accountQuotaDescription: String {
        provider.accountAvailableDescription
    }
}

private struct SidebarHeaderMetric: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 14)

                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ProviderDetailView: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var showingDeleteConfirmation = false
    @State private var showingConnectivitySheet = false
    @State private var showingEditSheet = false
    @State private var showingAddKeySheet = false
    @State private var connectivityInitialKeyID: UUID?
    @State private var cliProxyContentTab: CLIProxyContentTab = .codexAccounts

    let providerID: UUID

    var body: some View {
        if let provider = state.provider(id: providerID) {
            VStack(alignment: .leading, spacing: 22) {
                providerHero(provider)
                keyList(provider)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(28)
            .frame(maxWidth: 1_180, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.clear)
            .sheet(isPresented: $showingConnectivitySheet) {
                ModelConnectivitySheet(
                    providerID: providerID,
                    initialKeyID: connectivityInitialKeyID
                )
                .environmentObject(state)
            }
            .sheet(isPresented: $showingAddKeySheet) {
                AddAPIKeySheet(providerID: providerID)
                    .environmentObject(state)
            }
            .confirmationDialog("删除这个站点？", isPresented: $showingDeleteConfirmation) {
                Button("删除站点", role: .destructive) {
                    state.deleteProvider(providerID)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会同时删除这个站点下的 Key 和相关结果。")
            }
        } else {
            EmptyHintView(title: "站点不存在", message: "这个站点可能已经被删除。", systemImage: "questionmark.folder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func providerHero(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(provider.name)
                            .font(.system(size: 32, weight: .semibold))
                            .lineLimit(1)

                        StatusBadge(
                            status: provider.isEnabled ? .healthy : .disabled,
                            title: provider.isEnabled ? "已启用" : "已停用"
                        )

                        InlineInfoPill(title: provider.type.title, tint: .secondary)
                    }

                    Text(provider.displayBaseURL)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if state.isProviderWorking(provider.id) || state.providerStatusMessage(for: provider.id) != "就绪" {
                        Text(state.providerStatusMessage(for: provider.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if provider.requiresManualKeyCompletion {
                        Text("当前站点无法返回完整 Key，需要手动补全一次；后续同步会保留你补全的值。")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 16)

                providerMetrics(provider)
            }

            HStack(spacing: 10) {
                SettingsActionButton(title: "同步数据", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await state.syncManagedTokens(providerID: providerID) }
                }
                .disabled(state.isWorking)

                if provider.type == .openAICompatible {
                    SettingsActionButton(title: "添加 Key", systemImage: "plus") {
                        showingAddKeySheet = true
                    }
                    .disabled(state.isWorking)
                }

                if provider.type != .ccSwitch {
                    SettingsActionButton(title: "模型连通性", systemImage: "waveform.path.ecg.rectangle") {
                        openConnectivitySheet(for: provider.keys.first?.id)
                    }
                    .disabled(provider.keys.isEmpty)
                }

                SettingsActionButton(title: "编辑", systemImage: "slider.horizontal.3") {
                    showingEditSheet = true
                }
                .sheet(isPresented: $showingEditSheet) {
                    EditProviderSheet(providerID: providerID)
                        .environmentObject(state)
                }

                Spacer(minLength: 0)

                Toggle("启用", isOn: providerEnabledBinding)
                    .toggleStyle(CompactSwitchToggleStyle())

                SettingsActionButton(title: "删除站点", systemImage: "trash", isDestructive: true) {
                    showingDeleteConfirmation = true
                }
            }
            .disabled(state.isWorking)

            Rectangle()
                .fill(ModelsBarTheme.separator)
                .frame(height: 1)
        }
    }

    private func providerMetrics(_ provider: ProviderConfig) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SettingsMetricTile(title: provider.type == .ccSwitch ? "账号状态" : "Key 状态", value: statusCountDescription(provider), systemImage: provider.type == .ccSwitch ? "person.crop.circle.badge.checkmark" : "key.horizontal", tint: .green)
                SettingsMetricTile(title: "今日总消耗", value: todayUsageDescription(provider), systemImage: "calendar", tint: .blue)
            }

            HStack(spacing: 10) {
                SettingsMetricTile(title: "模型数量", value: "\(state.uniqueModelCount(providerID: provider.id))", systemImage: "cube.transparent", tint: .purple)
                SettingsMetricTile(title: "账号可用", value: availableQuotaDescription(provider), systemImage: "creditcard", tint: .mint)
            }
        }
        .frame(width: 306)
    }

    private func keyList(_ provider: ProviderConfig) -> some View {
        if provider.type == .cliProxy {
            return AnyView(cliProxyContentList(provider))
        }

        if provider.type == .ccSwitch {
            return AnyView(ccSwitchContentList(provider))
        }

        return AnyView(apiKeyList(provider))
    }

    private func apiKeyList(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(keyListTitle(provider))
                        .font(.headline.weight(.semibold))

                    Text(keyListSubtitle(provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Text(provider.type == .newapi ? "按令牌顺序展示，Key 额度和今日消耗会直接显示在卡片里。" : "授权后会自动同步账号下的全部 Keys，并使用 OpenAI completions 测试模型。")
                    //     .font(.caption)
                    //     .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Toggle("显示完整 Key", isOn: $state.revealsKeys)
                    .toggleStyle(CompactSwitchToggleStyle())
                    .disabled(provider.keys.isEmpty)
            }

            if provider.keys.isEmpty {
                EmptyHintView(title: "还没有 Key", message: emptyKeyMessage(provider), systemImage: "key")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(provider.keys) { apiKey in
                            APIKeyRow(
                                providerID: providerID,
                                keyID: apiKey.id
                            )
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cliProxyContentList(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                CLIProxyContentTabs(selection: $cliProxyContentTab)

                Spacer(minLength: 0)

                if cliProxyContentTab == .apiKeys {
                    Toggle("显示完整 Key", isOn: $state.revealsKeys)
                        .toggleStyle(CompactSwitchToggleStyle())
                        .disabled(provider.keys.isEmpty)
                }
            }

            switch cliProxyContentTab {
            case .apiKeys:
                apiKeyListContent(provider)

            case .codexAccounts:
                codexAccountListContent(provider)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func ccSwitchContentList(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex 账号")
                .font(.headline.weight(.semibold))

            codexAccountListContent(provider)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func apiKeyListContent(_ provider: ProviderConfig) -> some View {
        Group {
            if provider.keys.isEmpty {
                EmptyHintView(title: "还没有 Key", message: emptyKeyMessage(provider), systemImage: "key")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(provider.keys) { apiKey in
                            APIKeyRow(
                                providerID: providerID,
                                keyID: apiKey.id
                            )
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func codexAccountListContent(_ provider: ProviderConfig) -> some View {
        Group {
            if provider.codexAccounts.isEmpty {
                EmptyHintView(
                    title: "还没有 Codex 账号",
                    message: provider.type == .ccSwitch
                        ? "同步数据后会从 CC Switch 数据库读取 Codex official 账号，并独立刷新 5h / 周额度。"
                        : "同步数据后会从 auth 文件读取账号信息，并独立刷新 5h / 周额度。",
                    systemImage: "person.crop.rectangle.stack"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(provider.codexAccounts) { account in
                            CodexAccountRow(providerID: providerID, account: account)
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func keyListSubtitle(_ provider: ProviderConfig) -> String {
        switch provider.type {
        case .newapi:
            if provider.requiresManualKeyCompletion {
                return provider.keys.isEmpty
                    ? "同步后会导入脱敏 Key，随后需要手动补全。"
                    : "\(provider.keys.count) 个 Key，当前站点使用手动补全模式"
            }
            return provider.keys.isEmpty
                ? "同步系统访问令牌后会自动拉取可用 Key。"
                : "\(provider.keys.count) 个 Key"
        case .cliProxy:
            return provider.keys.isEmpty
                ? "同步管理密钥后会自动拉取 CLI Proxy API 下的全部 API Keys。"
                : "\(provider.keys.count) 个 API Key"
        case .ccSwitch:
            return provider.codexAccounts.isEmpty
                ? "同步后会读取 CC Switch 本地数据库中的 Codex official 账号。"
                : "\(provider.codexAccounts.count) 个 Codex official 账号"
        case .openAICompatible:
            return provider.keys.isEmpty
                ? "手动添加 API Key 后即可刷新模型并进行双接口测试。"
                : "\(provider.keys.count) 个 API Key"
        case .sub2api:
            if provider.sub2APIAuthorized == false {
                return "导入 Sub2API 登录态后即可同步账号下的全部 Key。"
            }
            return provider.keys.isEmpty
                ? "已导入登录态，点击同步即可拉取账号下的全部 Key。"
                : "\(provider.keys.count) 个 Key"
        }
    }

    private func emptyKeyMessage(_ provider: ProviderConfig) -> String {
        switch provider.type {
        case .newapi:
            return "配置系统访问令牌和用户ID后，同步即可拉取 Key。"
        case .cliProxy:
            return "配置 BaseURL 和管理密钥后，同步即可拉取 API Keys。"
        case .ccSwitch:
            return "配置 CC Switch 数据库路径后，同步即可读取 Codex official 账号。"
        case .openAICompatible:
            return "先点击上方“添加 Key”，再刷新模型列表。"
        case .sub2api:
            return provider.sub2APIAuthorized ? "点击同步数据即可拉取 Key。" : "先导入 Sub2API 登录态，再同步账号下的全部 Key。"
        }
    }

    private func keyListTitle(_ provider: ProviderConfig) -> String {
        switch provider.type {
        case .newapi:
            return "API Keys"
        case .cliProxy:
            return "CLI Proxy API Keys"
        case .ccSwitch:
            return "Codex 账号"
        case .openAICompatible:
            return "API Keys"
        case .sub2api:
            return "Sub2API Keys"
        }
    }

    private func openConnectivitySheet(for keyID: UUID?) {
        connectivityInitialKeyID = keyID
        showingConnectivitySheet = true
    }

    private func enabledKeyCount(_ provider: ProviderConfig) -> Int {
        provider.keys.filter(\.isEnabled).count
    }

    private func healthyKeyCount(_ provider: ProviderConfig) -> Int {
        provider.keys.filter { $0.lastStatus == .healthy }.count
    }

    private func statusCountDescription(_ provider: ProviderConfig) -> String {
        if provider.type == .ccSwitch {
            return "\(provider.codexAccounts.filter { $0.effectiveStatus == .healthy }.count)/\(provider.codexAccounts.count)"
        }

        return "\(healthyKeyCount(provider))/\(enabledKeyCount(provider))"
    }

    private func todayUsageDescription(_ provider: ProviderConfig) -> String {
        provider.totalTodayUsageDescription
    }

    private func availableQuotaDescription(_ provider: ProviderConfig) -> String {
        provider.accountAvailableDescription
    }

    private var providerEnabledBinding: Binding<Bool> {
        Binding {
            state.provider(id: providerID)?.isEnabled ?? false
        } set: { newValue in
            state.updateProvider(providerID) { $0.isEnabled = newValue }
        }
    }
}

private enum CLIProxyContentTab: String, CaseIterable, Identifiable {
    case codexAccounts
    case apiKeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiKeys:
            return "API Keys"
        case .codexAccounts:
            return "Codex 账号"
        }
    }
}

private struct CLIProxyContentTabs: View {
    @Binding var selection: CLIProxyContentTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CLIProxyContentTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == tab ? ModelsBarTheme.menuSurfaceStrong : ModelsBarTheme.menuSurface)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selection == tab ? ModelsBarTheme.menuBorder : ModelsBarTheme.menuBorderSoft, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct APIKeyRow: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var showingDeleteConfirmation = false
    @State private var isEditingManualKey = false
    @State private var manualKeyInput = ""

    let providerID: UUID
    let keyID: UUID

    var body: some View {
        if let apiKey = state.key(providerID: providerID, keyID: keyID) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text(apiKey.name)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)

                            if let tokenID = apiKey.managedTokenID {
                                InlineInfoPill(title: "ID \(tokenID)", tint: .secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            InlineMetric(title: "今日", value: todayUsageDescription(apiKey), tint: .blue)
                            InlineMetric(title: "Key 可用", value: availableQuotaDescription(apiKey), tint: .mint)
                            InlineMetric(title: "模型", value: "\(modelCount)", tint: .purple)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 10) {
                            StatusBadge(status: apiKey.isEnabled ? apiKey.lastStatus : .disabled)
                            Toggle("启用", isOn: enabledBinding)
                                .toggleStyle(CompactSwitchToggleStyle())
                                .labelsHidden()
                        }

                        if let checkedAt = apiKey.lastCheckedAt {
                            Text(checkedAt.shortDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                QuotaProgressView(apiKey: apiKey, providerType: providerType ?? .newapi)

                HStack(alignment: .center, spacing: 10) {
                    if isEditingManualKey {
                        SettingsTextField(
                            text: $manualKeyInput,
                            placeholder: "粘贴完整 Key",
                            monospaced: true,
                            enablesSelection: true
                        )

                        GlassIconButton(systemImage: "checkmark", isProminent: true) {
                            saveManualKey()
                        }
                        .help("保存补全后的 Key")

                        GlassIconButton(systemImage: "xmark") {
                            cancelManualKeyEditing()
                        }
                        .help("取消")
                    } else {
                        Text(state.revealsKeys ? displayAPIKey(for: apiKey) : maskedAPIKey(for: apiKey))
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SettingsInputBackground())

                        if supportsManualKeyEditing {
                            GlassIconButton(systemImage: "key.horizontal") {
                                beginManualKeyEditing(apiKey)
                            }
                            .help(needsManualCompletion(apiKey) ? "补全 Key" : "重新填写 Key")
                        }

                        GlassIconButton(systemImage: "doc.on.doc") {
                            copyAPIKey(apiKey)
                        }
                        .help(canCopyAPIKey(apiKey) ? "复制 Key" : "请先补全完整 Key")
                        .disabled(canCopyAPIKey(apiKey) == false)

                        GlassIconButton(systemImage: "arrow.clockwise") {
                            Task { await state.refreshKeyInfo(providerID: providerID, keyID: keyID) }
                        }
                        .help(canRefreshKey(apiKey) ? "刷新该 Key 的额度和模型" : "请先补全完整 Key")
                        .disabled(canRefreshKey(apiKey) == false)
                    }

                    GlassIconButton(systemImage: "trash", isDestructive: true) {
                        showingDeleteConfirmation = true
                    }
                    .help("删除 Key")
                }

                if needsManualCompletion(apiKey) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("当前只同步到了脱敏 Key，请手动补全完整 Key，之后同步不会覆盖你填写的值。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("补全 Key") {
                            beginManualKeyEditing(apiKey)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                    }
                }

            }
            .padding(16)
            .background(SettingsSurface(cornerRadius: 22, highlight: .subtle))
            .disabled(state.isWorking)
            .confirmationDialog("删除这个 Key？", isPresented: $showingDeleteConfirmation) {
                Button("删除 Key", role: .destructive) {
                    state.deleteKey(providerID: providerID, keyID: keyID)
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var modelCount: Int {
        state.modelRecords(providerID: providerID, keyID: keyID).count
    }

    private func availableQuotaDescription(_ apiKey: APIKeyConfig) -> String {
        providerType.map { apiKey.availableDescription(for: $0) } ?? "--"
    }

    private func todayUsageDescription(_ apiKey: APIKeyConfig) -> String {
        providerType.map { apiKey.todayUsageDescription(for: $0) } ?? "--"
    }

    private func copyAPIKey(_ apiKey: APIKeyConfig) {
        let copyableKey = displayAPIKey(for: apiKey)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyableKey, forType: .string)
        state.statusMessage = "已复制 \(apiKey.name)"
    }

    private func displayAPIKey(for apiKey: APIKeyConfig) -> String {
        apiKey.displayValue(for: providerType ?? .newapi)
    }

    private func maskedAPIKey(for apiKey: APIKeyConfig) -> String {
        apiKey.maskedValue(for: providerType ?? .newapi)
    }

    private func needsManualCompletion(_ apiKey: APIKeyConfig) -> Bool {
        providerType == .newapi && apiKey.requestValue(for: .newapi) == nil
    }

    private var supportsManualKeyEditing: Bool {
        providerType == .newapi || providerType == .openAICompatible
    }

    private func canCopyAPIKey(_ apiKey: APIKeyConfig) -> Bool {
        providerType != .newapi || apiKey.requestValue(for: .newapi) != nil
    }

    private func canRefreshKey(_ apiKey: APIKeyConfig) -> Bool {
        apiKey.isEnabled && (providerType != .newapi || apiKey.requestValue(for: .newapi) != nil)
    }

    private func beginManualKeyEditing(_ apiKey: APIKeyConfig) {
        manualKeyInput = needsManualCompletion(apiKey) ? "" : displayAPIKey(for: apiKey)
        isEditingManualKey = true
    }

    private func cancelManualKeyEditing() {
        manualKeyInput = ""
        isEditingManualKey = false
    }

    private func saveManualKey() {
        guard manualKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            state.statusMessage = "请先粘贴完整 Key"
            return
        }
        state.completeManualKey(providerID: providerID, keyID: keyID, value: manualKeyInput)
        cancelManualKeyEditing()
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            state.key(providerID: providerID, keyID: keyID)?.isEnabled ?? false
        } set: { newValue in
            state.updateKey(providerID: providerID, keyID: keyID) { $0.isEnabled = newValue }
        }
    }

    private var providerType: ProviderType? {
        state.provider(id: providerID)?.type
    }
}

private struct CodexAccountRow: View {
    @EnvironmentObject private var state: ModelsBarState
    @State private var isRefreshing = false

    let providerID: UUID
    let account: CodexAccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(account.email)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        InlineInfoPill(title: account.displayPlanType, tint: .secondary)
                    }

                    HStack(spacing: 8) {
                        if let accountID = account.shortAccountID {
                            InlineMetric(title: "账号", value: accountID, tint: .blue)
                        }
                        InlineMetric(title: "5h", value: account.fiveHourQuota.map { "已用 \($0.summaryDescription)" } ?? "--", tint: .mint)
                        InlineMetric(title: "周", value: account.weeklyQuota.map { "已用 \($0.summaryDescription)" } ?? "--", tint: .purple)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 10) {
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
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(isRefreshing ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("刷新此账号额度")
                        .disabled(isRefreshing)

                        StatusBadge(status: account.effectiveStatus)
                    }

                    if let quotaCheckedAt = account.quotaCheckedAt {
                        Text(quotaCheckedAt.shortDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let authRefreshedAt = account.authRefreshedAt {
                        Text(authRefreshedAt.shortDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                CodexQuotaCard(quota: account.fiveHourQuota, accent: .mint)
                CodexQuotaCard(quota: account.weeklyQuota, accent: .purple)
            }
        }
        .padding(16)
        .background(SettingsSurface(cornerRadius: 22, highlight: .subtle))
    }
}

private struct CodexQuotaCard: View {
    let quota: CodexQuotaSnapshot?
    let accent: Color

    var body: some View {
        let tint = quota?.isDangerouslyLow == true ? Color.red : accent

        VStack(alignment: .leading, spacing: 8) {
            Text(quota?.title ?? "--")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(quota?.summaryDescription ?? "--")
                .font(.title3.weight(.semibold).monospacedDigit())

            Text(quota?.detailDescription ?? "暂不可用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ModelsBarTheme.progressTrack)

                    Capsule()
                        .fill(tint.opacity(0.88))
                        .frame(width: max(10, proxy.size.width * CGFloat(quota?.progressValue ?? 0.02)))
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
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

private struct ModelConnectivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: ModelsBarState
    @State private var selectedKeyID: UUID?

    let providerID: UUID

    init(providerID: UUID, initialKeyID: UUID?) {
        self.providerID = providerID
        _selectedKeyID = State(initialValue: initialKeyID)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsWindowBackground()

            if let provider = state.provider(id: providerID) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型连通性")
                                .font(.title2.weight(.semibold))
                            Text(provider.name)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        if state.isProviderWorking(provider.id) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(state.providerStatusMessage(for: provider.id))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(state.providerStatusMessage(for: provider.id))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        GlassIconButton(systemImage: "xmark") {
                            dismiss()
                        }
                        .help("关闭")
                    }

                    if provider.keys.isEmpty {
                        EmptyHintView(title: "还没有可测试的 Key", message: connectivityEmptyMessage(provider), systemImage: "key.horizontal")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(provider.keys) { apiKey in
                                    ConnectivityTabButton(
                                        title: apiKey.name,
                                        subtitle: "\(state.modelRecords(providerID: provider.id, keyID: apiKey.id).count) 个模型",
                                        isSelected: selectedKeyID == apiKey.id
                                    ) {
                                        selectedKeyID = apiKey.id
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        if let apiKey = selectedKey(provider) {
                            ConnectivityKeyPanel(provider: provider, apiKey: apiKey)
                        } else {
                            CompactEmptyRow(title: "请选择一个 Key", systemImage: "cursorarrow.click")
                        }
                    }
                }
                .padding(24)
                .frame(width: 980, height: preferredHeight(for: provider), alignment: .topLeading)
                .onAppear {
                    ensureSelection(in: provider)
                }
                .onChange(of: provider.keys.map(\.id)) {
                    ensureSelection(in: provider)
                }
            }
        }
    }

    private func selectedKey(_ provider: ProviderConfig) -> APIKeyConfig? {
        if let selectedKeyID,
           let selected = provider.keys.first(where: { $0.id == selectedKeyID }) {
            return selected
        }

        return provider.keys.first
    }

    private func ensureSelection(in provider: ProviderConfig) {
        guard provider.keys.isEmpty == false else {
            selectedKeyID = nil
            return
        }

        if let selectedKeyID,
           provider.keys.contains(where: { $0.id == selectedKeyID }) {
            return
        }

        selectedKeyID = provider.keys.first?.id
    }

    private func preferredHeight(for provider: ProviderConfig) -> CGFloat {
        let headerHeight: CGFloat = 132
        let tabsHeight: CGFloat = provider.keys.isEmpty ? 0 : 58
        let panelHeight: CGFloat

        if provider.keys.isEmpty {
            panelHeight = 150
        } else if let apiKey = selectedKey(provider) {
            let recordCount = state.modelRecords(providerID: provider.id, keyID: apiKey.id).count
            if recordCount == 0 {
                panelHeight = 258
            } else {
                let visibleRows = min(recordCount, 5)
                panelHeight = min(248 + CGFloat(visibleRows) * 96, 620)
            }
        } else {
            panelHeight = 150
        }

        return min(max(headerHeight + tabsHeight + panelHeight, 420), 760)
    }

    private func connectivityEmptyMessage(_ provider: ProviderConfig) -> String {
        switch provider.type {
        case .newapi:
            return "先同步系统访问令牌，或手动添加一个 Key。"
        case .cliProxy:
            return "先同步 CLI Proxy API 管理端里的 API Keys。"
        case .ccSwitch:
            return "CC Switch 站点只展示 Codex official 账号额度，不进行模型连通性测试。"
        case .openAICompatible:
            return "先手动添加一个 API Key，再刷新模型列表。"
        case .sub2api:
            return "先完成授权并同步账号 Keys。"
        }
    }
}

private struct ConnectivityKeyPanel: View {
    @EnvironmentObject private var state: ModelsBarState

    let provider: ProviderConfig
    let apiKey: APIKeyConfig

    var body: some View {
        let records = state.modelRecords(providerID: provider.id, keyID: apiKey.id)

        SettingsGlassCard(highlight: .subtle) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(apiKey.name)
                                .font(.title3.weight(.semibold))
                            StatusBadge(status: apiKey.isEnabled ? apiKey.lastStatus : .disabled)
                        }

                        Text(apiKey.maskedValue(for: provider.type))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        InlineMetric(title: "模型", value: "\(records.count)", tint: .purple)
                        InlineMetric(title: "今日", value: apiKey.todayUsageDescription(for: provider.type), tint: .blue)
                        InlineMetric(title: "Key 可用", value: availableQuotaDescription(apiKey), tint: .mint)
                    }
                }

                HStack(spacing: 10) {
                    SettingsActionButton(title: "刷新", systemImage: "arrow.clockwise") {
                        Task { await state.refreshKeyInfo(providerID: provider.id, keyID: apiKey.id) }
                    }
                    .disabled(state.isWorking || canRefreshKey == false)

                    Spacer(minLength: 0)
                }

                if records.isEmpty {
                    ConnectivityEmptyState(
                        title: canRefreshKey ? "还没有模型" : "这个 Key 还没补全",
                        message: canRefreshKey ? "先刷新一次模型列表，再进行单模型测试。" : "回到设置页为这个 Key 补全完整值，再刷新模型和额度。",
                        systemImage: canRefreshKey ? "cube.transparent" : "key.horizontal"
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(records) { record in
                                ConnectivityModelRow(provider: provider, apiKey: apiKey, record: record)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 520)
                }
            }
        }
    }

    private func availableQuotaDescription(_ apiKey: APIKeyConfig) -> String {
        apiKey.availableDescription(for: provider.type)
    }

    private var canRefreshKey: Bool {
        provider.type != .newapi || apiKey.requestValue(for: .newapi) != nil
    }
}

private struct ConnectivityModelRow: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: modelSymbol)
                    .foregroundStyle(modelTint)
                    .frame(width: 16)

                Text(record.modelID)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if availableInterfaces.count > 1 {
                    Picker("接口", selection: $selectedInterface) {
                        ForEach(availableInterfaces, id: \.self) { interface in
                            Text(interface.shortTitle).tag(interface)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: interfacePickerWidth, alignment: .trailing)
                    .help("选择测试接口")
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    statusPill(currentResult(for: .nonStream), prefix: "非流式")
                    if supportsStreamTesting {
                        statusPill(currentResult(for: .stream), prefix: "流式")
                    } else {
                        unsupportedStatusPill(prefix: "流式")
                    }
                }

                Spacer(minLength: 0)

                SettingsActionButton(
                    title: buttonTitle(for: .nonStream),
                    systemImage: buttonImage(for: .nonStream),
                    compact: true
                ) {
                    state.enqueueModelTest(
                        providerID: provider.id,
                        keyID: apiKey.id,
                        modelID: record.modelID,
                        mode: .nonStream,
                        interface: selectedInterface
                    )
                }
                .disabled(buttonDisabled(for: .nonStream))

                SettingsActionButton(
                    title: buttonTitle(for: .stream),
                    systemImage: buttonImage(for: .stream),
                    compact: true
                ) {
                    state.enqueueModelTest(
                        providerID: provider.id,
                        keyID: apiKey.id,
                        modelID: record.modelID,
                        mode: .stream,
                        interface: selectedInterface
                    )
                }
                .disabled(buttonDisabled(for: .stream))
                .help(supportsStreamTesting ? "测试流式响应" : "\(selectedInterface.shortTitle) 不支持流式测试")
            }

            Text("当前接口：\(selectedInterface.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(SettingsSurface(cornerRadius: 18, highlight: .soft))
    }

    private var availableInterfaces: [OpenAIModelInterface] {
        OpenAIModelInterface.availableInterfaces(for: record.modelID)
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

    private var statusResults: [ModelTestResult] {
        supportsStreamTesting
            ? [currentResult(for: .nonStream), currentResult(for: .stream)].compactMap(\.self)
            : [currentResult(for: .nonStream)].compactMap(\.self)
    }

    private var expectedStatusResultCount: Int {
        supportsStreamTesting ? 2 : 1
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

    private func statusPill(_ result: ModelTestResult?, prefix: String) -> some View {
        Label(statusTitle(result, prefix: prefix), systemImage: statusSymbol(result))
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusTint(result))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusTint(result).opacity(0.14), in: Capsule())
    }

    private func unsupportedStatusPill(prefix: String) -> some View {
        Label("\(prefix)：不支持", systemImage: "nosign")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
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

    private func executionState(for mode: TestMode) -> ModelTestExecutionState {
        state.modelTestExecutionState(
            providerID: provider.id,
            keyID: apiKey.id,
            modelID: record.modelID,
            mode: mode,
            interface: selectedInterface
        )
    }

    private func buttonTitle(for mode: TestMode) -> String {
        switch executionState(for: mode) {
        case .idle:
            return mode == .nonStream ? "测非流式" : "测流式"
        case .queued:
            return "排队中"
        case .running:
            return "测试中"
        }
    }

    private func buttonImage(for mode: TestMode) -> String {
        switch executionState(for: mode) {
        case .idle:
            return mode == .nonStream ? "bolt.horizontal" : "waveform"
        case .queued, .running:
            return "hourglass"
        }
    }

    private func buttonDisabled(for mode: TestMode) -> Bool {
        if mode == .stream && supportsStreamTesting == false {
            return true
        }

        switch executionState(for: mode) {
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

private struct ConnectivityEmptyState: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(ModelsBarTheme.controlBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsSurface(cornerRadius: 20, highlight: .soft))
    }
}

private struct SettingsWelcomeView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("添加一个站点")
                .font(.title2.weight(.semibold))

            Text("配置 BaseURL 后，按站点类型填写系统令牌或导入 Sub2API 登录态，即可同步账号额度、Key 额度和模型。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 460)
        .background(SettingsSurface(cornerRadius: 28, highlight: .soft))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsWindowBackground: View {
    var body: some View {
        ZStack {
            ModelsBarTheme.settingsWindowBackground

            LinearGradient(
                colors: [
                    ModelsBarTheme.settingsGradientStart,
                    ModelsBarTheme.settingsGradientMiddle,
                    ModelsBarTheme.settingsGradientEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 90)

            RadialGradient(
                colors: [
                    ModelsBarTheme.settingsGlow,
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            .blur(radius: 22)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
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

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = ModelsBarTheme.nsSettingsWindowBackground
        window.isOpaque = false
        window.identifier = modelsBarSettingsWindowIdentifier
        window.styleMask.insert(.fullSizeContentView)
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
    }
}

private struct SettingsGlassCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    var highlight: SurfaceHighlight = .subtle
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        highlight: SurfaceHighlight = .subtle,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.highlight = highlight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(20)
        .background(SettingsSurface(cornerRadius: 28, highlight: highlight))
    }
}

private enum SurfaceHighlight {
    case hero
    case subtle
    case soft
}

private struct SettingsSurface: View {
    let cornerRadius: CGFloat
    let highlight: SurfaceHighlight

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillGradient)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: 24, y: 14)
    }

    private var fillGradient: LinearGradient {
        switch highlight {
        case .hero:
            return LinearGradient(
                colors: [
                    ModelsBarTheme.surfaceHeroStart,
                    ModelsBarTheme.surfaceHeroEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .subtle:
            return LinearGradient(
                colors: [
                    ModelsBarTheme.surfaceSubtleStart,
                    ModelsBarTheme.surfaceSubtleEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .soft:
            return LinearGradient(
                colors: [
                    ModelsBarTheme.surfaceSoftStart,
                    ModelsBarTheme.surfaceSoftEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch highlight {
        case .hero: return ModelsBarTheme.surfaceHeroBorder
        case .subtle: return ModelsBarTheme.surfaceSubtleBorder
        case .soft: return ModelsBarTheme.surfaceSoftBorder
        }
    }

    private var shadowColor: Color {
        switch highlight {
        case .hero: return ModelsBarTheme.surfaceHeroShadow
        case .subtle: return ModelsBarTheme.surfaceSubtleShadow
        case .soft: return ModelsBarTheme.surfaceSoftShadow
        }
    }
}

private struct SettingsFieldBlock<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsTextField: View {
    @Binding var text: String
    var placeholder: String
    var monospaced = false
    var enablesSelection = false

    var body: some View {
        Group {
            if enablesSelection {
                TextField(placeholder, text: $text)
                    .textSelection(.enabled)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? .system(.body, design: .monospaced) : .body)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsInputBackground())
    }
}

private struct SettingsInputBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(ModelsBarTheme.inputBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ModelsBarTheme.inputBorder, lineWidth: 1)
            }
    }
}

private struct SettingsMetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InlineMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct InlineInfoPill: View {
    var title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct QuotaProgressView: View {
    let apiKey: APIKeyConfig
    let providerType: ProviderType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Key 额度")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(quotaSummary)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ModelsBarTheme.progressTrack)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [progressTint.opacity(0.96), progressTint.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, proxy.size.width * progress))
                }
            }
            .frame(height: 8)
        }
    }

    private var quotaSummary: String {
        apiKey.quotaSummary(for: providerType)
    }

    private var progress: CGFloat {
        CGFloat(apiKey.quotaProgress(for: providerType))
    }

    private var progressTint: Color {
        if quotaSummary == "--" {
            return .secondary
        }

        if quotaSummary == "无限额度" {
            return .green
        }

        switch apiKey.quotaProgress(for: providerType) {
        case 0..<0.15:
            return .red
        case 0..<0.35:
            return .yellow
        default:
            return .green
        }
    }
}

private struct SettingsActionButton: View {
    var title: String
    var systemImage: String
    var isDestructive = false
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font((compact ? Font.caption : Font.callout).weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, compact ? 12 : 14)
                .frame(height: compact ? 34 : nil)
                .padding(.vertical, compact ? 0 : 10)
                .foregroundStyle(isDestructive ? Color.red.opacity(0.96) : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                        .fill(isDestructive ? Color.red.opacity(0.10) : ModelsBarTheme.controlBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                        .stroke(isDestructive ? Color.red.opacity(0.18) : ModelsBarTheme.controlBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct GlassIconButton: View {
    var systemImage: String
    var isProminent = false
    var isDestructive = false
    var showsBorder = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassIconButtonFace(
                systemImage: systemImage,
                isProminent: isProminent,
                isDestructive: isDestructive,
                showsBorder: showsBorder
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderSymbolButton: View {
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderSymbolLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderSymbolLabel: View {
    var systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 18, height: 34)
            .contentShape(Rectangle())
    }
}

private struct GlassIconButtonFace: View {
    var systemImage: String
    var isProminent = false
    var isDestructive = false
    var showsBorder = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
            }
    }

    private var iconColor: Color {
        if isDestructive {
            return .red.opacity(0.94)
        }
        return isProminent ? .white : .primary
    }

    private var backgroundColor: Color {
        if isDestructive {
            return .red.opacity(0.12)
        }
        return isProminent ? Color.accentColor.opacity(0.92) : ModelsBarTheme.controlBackground
    }

    private var borderColor: Color {
        if isDestructive {
            return .red.opacity(0.18)
        }
        return isProminent ? Color.white.opacity(0.14) : ModelsBarTheme.controlBorder
    }
}

private struct ConnectivityTabButton: View {
    var title: String
    var subtitle: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.94)
                            : ModelsBarTheme.controlBackground
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.16) : ModelsBarTheme.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CompactSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label

            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.accentColor.opacity(0.96) : ModelsBarTheme.inactiveSwitchTrack)
                        .frame(width: 38, height: 22)

                    Circle()
                        .fill(ModelsBarTheme.switchThumb)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompactEmptyRow: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct ProviderTypePicker: View {
    @Binding var selection: ProviderType
    var isEditable = true

    var body: some View {
        ProviderTypePopupButton(selection: $selection, isEditable: isEditable)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
        .disabled(isEditable == false)
    }
}

private struct ProviderTypePopupButton: NSViewRepresentable {
    @Binding var selection: ProviderType
    var isEditable: Bool

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        ProviderType.allCases.forEach { type in
            button.addItem(withTitle: type.title)
        }
        return button
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if nsView.itemTitles != ProviderType.allCases.map(\.title) {
            nsView.removeAllItems()
            ProviderType.allCases.forEach { type in
                nsView.addItem(withTitle: type.title)
            }
        }
        nsView.selectItem(withTitle: selection.title)
        nsView.isEnabled = isEditable
        nsView.alphaValue = isEditable ? 1 : 0.72
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<ProviderType>

        init(selection: Binding<ProviderType>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let selectedType = ProviderType.allCases.first(where: { $0.title == sender.titleOfSelectedItem }) else {
                return
            }
            selection.wrappedValue = selectedType
        }
    }
}

private struct Sub2APIAuthorizationDraft: Equatable {
    var baseURL: String
    var accessToken: String
    var refreshToken: String
    var tokenExpiresAt: String
}

private struct Sub2APIAuthorizationImportSection: View {
    @Binding var accessToken: String
    @Binding var refreshToken: String
    @Binding var tokenExpiresAt: String

    var baseURL: String
    var authorization: Sub2APIAuthorizationSession?
    var isCurrentAuthorization: Bool
    var errorMessage: String?

    private var hasBaseURL: Bool {
        normalizedSub2APIField(baseURL).isEmpty == false
    }

    var body: some View {
        Group {
            SettingsFieldBlock(title: "复制说明") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        hasBaseURL
                            ? "先在浏览器登录当前站点，再打开 F12 -> Application 或 Storage -> Local Storage -> 当前站点域名，复制下面 3 个键值。"
                            : "先输入 BaseURL，再去浏览器登录该站点，然后从 F12 的 Local Storage 里复制登录态。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Sub2APIImportKeyRow(key: "auth_token", detail: "当前访问令牌")
                        Sub2APIImportKeyRow(key: "refresh_token", detail: "刷新令牌")
                        Sub2APIImportKeyRow(key: "token_expires_at", detail: "过期时间戳，通常是毫秒值")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsInputBackground())
            }

            SettingsFieldBlock(title: "auth_token") {
                SettingsTextField(
                    text: $accessToken,
                    placeholder: "浏览器 Local Storage 中的 auth_token",
                    monospaced: true,
                    enablesSelection: true
                )
            }

            SettingsFieldBlock(title: "refresh_token") {
                SettingsTextField(
                    text: $refreshToken,
                    placeholder: "浏览器 Local Storage 中的 refresh_token",
                    monospaced: true,
                    enablesSelection: true
                )
            }

            SettingsFieldBlock(title: "token_expires_at") {
                SettingsTextField(
                    text: $tokenExpiresAt,
                    placeholder: "浏览器 Local Storage 中的 token_expires_at，可留空",
                    monospaced: true,
                    enablesSelection: true
                )
            }

            if let authorization {
                SettingsFieldBlock(title: "当前登录态") {
                    Sub2APIAuthorizationStatusView(
                        authorization: authorization,
                        isCurrentAuthorization: isCurrentAuthorization
                    )
                }
            }

            if let errorMessage {
                SettingsFieldBlock(title: "校验结果") {
                    Sub2APIAuthorizationMessageView(
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .yellow,
                        message: errorMessage
                    )
                }
            }
        }
    }
}

private struct Sub2APIImportKeyRow: View {
    var key: String
    var detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Sub2APIAuthorizationStatusView: View {
    var authorization: Sub2APIAuthorizationSession
    var isCurrentAuthorization: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                InlineInfoPill(
                    title: isCurrentAuthorization ? "已校验" : "待重新校验",
                    tint: isCurrentAuthorization ? .green : .yellow
                )

                if let tokenExpiresAt = authorization.tokenExpiresAt {
                    Text("到期 \(tokenExpiresAt.shortDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(authorization.user.displayName)
                .font(.callout.weight(.semibold))

            Text("\(authorization.user.email) · \(authorization.user.availableDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isCurrentAuthorization == false {
                Text("当前 BaseURL 或 token 已改动，保存时会重新校验这组登录态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsInputBackground())
    }
}

private struct Sub2APIAuthorizationMessageView: View {
    var systemImage: String
    var tint: Color
    var message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsInputBackground())
    }
}

private struct Sub2APITokenExpiresAtParseError: LocalizedError {
    var errorDescription: String? {
        "token_expires_at 格式无效，请直接粘贴浏览器 Local Storage 里的原始值。"
    }
}

private func normalizedSub2APIField(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func providerEndpointFieldTitle(_ providerType: ProviderType) -> String {
    providerType == .ccSwitch ? "数据库路径" : "BaseURL"
}

private func providerEndpointPlaceholder(_ providerType: ProviderType) -> String {
    providerType == .ccSwitch ? CCSwitchCodexAccountService.defaultDatabasePath : "https://example.com"
}

private func normalizedBaseURLField(_ value: String, providerType: ProviderType? = nil) -> String {
    let trimmed = normalizedSub2APIField(value)
    guard let providerType else {
        return trimmed
    }

    if providerType == .cliProxy {
        return CLIProxyManagementClient.normalizedBaseURLString(trimmed)
    }

    return trimmed
}

private func formatSub2APITokenExpiresAtInput(_ date: Date) -> String {
    String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
}

private func parseSub2APITokenExpiresAtInput(_ rawValue: String) throws -> Date? {
    let trimmed = normalizedSub2APIField(rawValue)
    guard trimmed.isEmpty == false else {
        return nil
    }

    if let timestamp = Double(trimmed) {
        if timestamp >= 10_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000)
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: trimmed) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: trimmed) {
        return date
    }

    throw Sub2APITokenExpiresAtParseError()
}

private func makeSub2APIAuthorizationDraft(
    baseURL: String,
    accessToken: String,
    refreshToken: String,
    tokenExpiresAt: String
) -> Sub2APIAuthorizationDraft {
    Sub2APIAuthorizationDraft(
        baseURL: normalizedSub2APIField(baseURL),
        accessToken: normalizedSub2APIField(accessToken),
        refreshToken: normalizedSub2APIField(refreshToken),
        tokenExpiresAt: normalizedSub2APIField(tokenExpiresAt)
    )
}

@MainActor
private func validateSub2APIAuthorizationDraft(
    state: ModelsBarState,
    baseURL: String,
    accessToken: String,
    refreshToken: String,
    tokenExpiresAt: String
) async throws -> (session: Sub2APIAuthorizationSession, draft: Sub2APIAuthorizationDraft) {
    let draft = makeSub2APIAuthorizationDraft(
        baseURL: baseURL,
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenExpiresAt: tokenExpiresAt
    )
    let parsedTokenExpiresAt = try parseSub2APITokenExpiresAtInput(draft.tokenExpiresAt)
    let session = try await state.validateSub2APIAuthorization(
        baseURL: draft.baseURL,
        accessToken: draft.accessToken,
        refreshToken: draft.refreshToken,
        tokenExpiresAt: parsedTokenExpiresAt
    )
    return (session, draft)
}

private struct AddAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: ModelsBarState
    @State private var name = ""
    @State private var apiKey = ""
    @State private var isSaving = false

    let providerID: UUID

    var body: some View {
        ZStack {
            SettingsWindowBackground()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("添加 API Key")
                        .font(.title3.weight(.semibold))
                    Text("新增后会立即刷新这个 Key 的模型列表，并接入现有的双接口测试。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsFieldBlock(title: "名称") {
                    SettingsTextField(text: $name, placeholder: defaultKeyName)
                }

                SettingsFieldBlock(title: "API Key") {
                    SettingsTextField(
                        text: $apiKey,
                        placeholder: "sk-... 或其他兼容 Key",
                        monospaced: true,
                        enablesSelection: true
                    )
                }

                HStack {
                    SettingsActionButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)

                    Spacer(minLength: 0)

                    SettingsActionButton(title: isSaving ? "添加中" : "添加 Key", systemImage: "plus") {
                        isSaving = true

                        Task { @MainActor in
                            let keyID = state.addKey(
                                providerID: providerID,
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultKeyName : name,
                                value: apiKey
                            )
                            await state.refreshKeyInfo(providerID: providerID, keyID: keyID)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(28)
            .frame(width: 480)
        }
        .onAppear {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = defaultKeyName
            }
        }
    }

    private var defaultKeyName: String {
        let nextIndex = (state.provider(id: providerID)?.keys.count ?? 0) + 1
        return "API Key \(nextIndex)"
    }
}

private struct EditProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: ModelsBarState
    @State private var providerType: ProviderType = .newapi
    @State private var name = ""
    @State private var baseURL = ""
    @State private var managementToken = ""
    @State private var managementUserID = ""
    @State private var sub2APIAccessToken = ""
    @State private var sub2APIRefreshToken = ""
    @State private var sub2APITokenExpiresAt = ""
    @State private var sub2APIAuthorization: Sub2APIAuthorizationSession?
    @State private var sub2APIAuthorizedDraft: Sub2APIAuthorizationDraft?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    let providerID: UUID

    var body: some View {
        ZStack {
            SettingsWindowBackground()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("编辑站点")
                        .font(.title3.weight(.semibold))
                    Text(editProviderSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsFieldBlock(title: "站点类型") {
                    ProviderTypePicker(selection: $providerType, isEditable: false)
                }

                SettingsFieldBlock(title: "名称") {
                    SettingsTextField(text: $name, placeholder: providerType.defaultProviderName)
                }

                SettingsFieldBlock(title: providerEndpointFieldTitle(providerType)) {
                    SettingsTextField(
                        text: $baseURL,
                        placeholder: providerEndpointPlaceholder(providerType),
                        monospaced: true,
                        enablesSelection: true
                    )
                }

                if providerType == .newapi || providerType == .cliProxy {
                    SettingsFieldBlock(title: "系统访问令牌") {
                        SettingsTextField(
                            text: $managementToken,
                            placeholder: providerType == .cliProxy ? "Management Key" : "个人设置 - 安全设置 - 系统访问令牌",
                            monospaced: true,
                            enablesSelection: true
                        )
                    }

                    if providerType == .newapi {
                        SettingsFieldBlock(title: "用户ID") {
                            SettingsTextField(text: $managementUserID, placeholder: "用户ID")
                        }
                    }
                } else if providerType == .openAICompatible {
                    SettingsFieldBlock(title: "API Key") {
                        Text("这个类型的 API Keys 在站点详情页中单独管理。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(SettingsInputBackground())
                    }
                } else if providerType == .ccSwitch {
                    SettingsFieldBlock(title: "说明") {
                        Text("将从本机 CC Switch SQLite 数据库读取 Codex official 登录信息，自定义第三方 Codex Provider 会被跳过。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(SettingsInputBackground())
                    }
                } else {
                    Sub2APIAuthorizationImportSection(
                        accessToken: $sub2APIAccessToken,
                        refreshToken: $sub2APIRefreshToken,
                        tokenExpiresAt: $sub2APITokenExpiresAt,
                        baseURL: baseURL,
                        authorization: sub2APIAuthorization,
                        isCurrentAuthorization: currentSub2APIAuthorizationDraft == sub2APIAuthorizedDraft,
                        errorMessage: saveErrorMessage
                    )
                }

                HStack {
                    SettingsActionButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)

                    Spacer(minLength: 0)

                    SettingsActionButton(title: isSaving ? "保存中" : "保存", systemImage: "checkmark") {
                        isSaving = true
                        saveErrorMessage = nil

                        Task { @MainActor in
                            do {
                                let trimmedBaseURL = normalizedBaseURLField(baseURL, providerType: providerType)
                                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedToken = managementToken.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedUserID = managementUserID.trimmingCharacters(in: .whitespacesAndNewlines)
                                let previousProvider = state.provider(id: providerID)
                                let validatedSub2APIAuthorization: Sub2APIAuthorizationSession?
                                let validatedSub2APIDraft: Sub2APIAuthorizationDraft?

                                switch providerType {
                                case .newapi:
                                    validatedSub2APIAuthorization = nil
                                    validatedSub2APIDraft = nil
                                case .cliProxy:
                                    validatedSub2APIAuthorization = nil
                                    validatedSub2APIDraft = nil
                                case .openAICompatible:
                                    validatedSub2APIAuthorization = nil
                                    validatedSub2APIDraft = nil
                                case .ccSwitch:
                                    validatedSub2APIAuthorization = nil
                                    validatedSub2APIDraft = nil
                                case .sub2api:
                                    let validation = try await validateSub2APIAuthorizationDraft(
                                        state: state,
                                        baseURL: baseURL,
                                        accessToken: sub2APIAccessToken,
                                        refreshToken: sub2APIRefreshToken,
                                        tokenExpiresAt: sub2APITokenExpiresAt
                                    )
                                    validatedSub2APIAuthorization = validation.session
                                    validatedSub2APIDraft = validation.draft
                                }

                                let shouldResetSyncResults = providerType == .sub2api && (
                                    previousProvider?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedBaseURL ||
                                    previousProvider?.sub2APIRefreshToken != validatedSub2APIAuthorization?.refreshToken
                                )
                                let nextManagementToken = trimmedToken.isEmpty ? nil : trimmedToken
                                let nextManagementUserID = trimmedUserID.isEmpty ? nil : trimmedUserID
                                let accountIdentityChanged = previousProvider?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedBaseURL ||
                                    previousProvider?.managementToken != nextManagementToken ||
                                    previousProvider?.managementUserID != nextManagementUserID

                                state.updateProvider(providerID) { provider in
                                    provider.name = trimmedName.isEmpty ? providerType.defaultProviderName : trimmedName
                                    provider.baseURL = trimmedBaseURL

                                    switch providerType {
                                    case .newapi:
                                        provider.managementToken = nextManagementToken
                                        provider.managementUserID = nextManagementUserID
                                        provider.sub2APIAccessToken = nil
                                        provider.sub2APIRefreshToken = nil
                                        provider.sub2APITokenExpiresAt = nil
                                        provider.sub2APIUser = nil

                                        if accountIdentityChanged {
                                            provider.accountQuota = nil
                                        }

                                    case .cliProxy:
                                        provider.managementToken = nextManagementToken
                                        provider.managementUserID = nil
                                        provider.accountQuota = nil
                                        provider.sub2APIAccessToken = nil
                                        provider.sub2APIRefreshToken = nil
                                        provider.sub2APITokenExpiresAt = nil
                                        provider.sub2APIUser = nil
                                        if accountIdentityChanged {
                                            provider.keys.removeAll()
                                            provider.codexAccounts.removeAll()
                                        }

                                    case .openAICompatible:
                                        provider.managementToken = nil
                                        provider.managementUserID = nil
                                        provider.accountQuota = nil
                                        provider.sub2APIAccessToken = nil
                                        provider.sub2APIRefreshToken = nil
                                        provider.sub2APITokenExpiresAt = nil
                                        provider.sub2APIUser = nil

                                    case .ccSwitch:
                                        provider.managementToken = nil
                                        provider.managementUserID = nil
                                        provider.accountQuota = nil
                                        provider.sub2APIAccessToken = nil
                                        provider.sub2APIRefreshToken = nil
                                        provider.sub2APITokenExpiresAt = nil
                                        provider.sub2APIUser = nil
                                        provider.keys.removeAll()
                                        if accountIdentityChanged {
                                            provider.codexAccounts.removeAll()
                                        }

                                    case .sub2api:
                                        provider.managementToken = nil
                                        provider.managementUserID = nil
                                        provider.accountQuota = nil
                                        provider.sub2APIAccessToken = validatedSub2APIAuthorization?.accessToken
                                        provider.sub2APIRefreshToken = validatedSub2APIAuthorization?.refreshToken
                                        provider.sub2APITokenExpiresAt = validatedSub2APIAuthorization?.tokenExpiresAt
                                        provider.sub2APIUser = validatedSub2APIAuthorization?.user
                                        if shouldResetSyncResults {
                                            provider.keys.removeAll()
                                        }
                                    }
                                }

                                if shouldResetSyncResults {
                                    state.clearProviderSyncResults(providerID)
                                }

                                sub2APIAuthorization = validatedSub2APIAuthorization
                                sub2APIAuthorizedDraft = validatedSub2APIDraft
                                isSaving = false
                                dismiss()
                            } catch {
                                saveErrorMessage = error.localizedDescription
                                isSaving = false
                            }
                        }
                    }
                    .disabled(
                        isSaving || isSaveDisabled
                    )
                }
            }
            .padding(28)
            .frame(width: 520)
        }
        .onAppear {
            guard let provider = state.provider(id: providerID) else {
                return
            }
            name = provider.name
            providerType = provider.type
            baseURL = provider.baseURL
            managementToken = provider.managementToken ?? ""
            managementUserID = provider.managementUserID ?? ""
            sub2APIAccessToken = provider.sub2APIAccessToken ?? ""
            sub2APIRefreshToken = provider.sub2APIRefreshToken ?? ""
            sub2APITokenExpiresAt = provider.sub2APITokenExpiresAt.map(formatSub2APITokenExpiresAtInput) ?? ""
            if provider.type == .sub2api,
               let accessToken = provider.sub2APIAccessToken,
               let refreshToken = provider.sub2APIRefreshToken,
               let user = provider.sub2APIUser {
                sub2APIAuthorization = Sub2APIAuthorizationSession(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    tokenExpiresAt: provider.sub2APITokenExpiresAt,
                    user: user
                )
                sub2APIAuthorizedDraft = makeSub2APIAuthorizationDraft(
                    baseURL: provider.baseURL,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    tokenExpiresAt: provider.sub2APITokenExpiresAt.map(formatSub2APITokenExpiresAtInput) ?? ""
                )
            } else {
                sub2APIAuthorization = nil
                sub2APIAuthorizedDraft = nil
            }
        }
    }

    private var isSaveDisabled: Bool {
        let trimmedBaseURL = normalizedBaseURLField(baseURL, providerType: providerType)
        switch providerType {
        case .newapi:
            return trimmedBaseURL.isEmpty ||
                managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                managementUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cliProxy:
            return trimmedBaseURL.isEmpty ||
                managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openAICompatible:
            return trimmedBaseURL.isEmpty
        case .ccSwitch:
            return trimmedBaseURL.isEmpty
        case .sub2api:
            return trimmedBaseURL.isEmpty ||
                normalizedSub2APIField(sub2APIAccessToken).isEmpty ||
                normalizedSub2APIField(sub2APIRefreshToken).isEmpty
        }
    }

    private var currentSub2APIAuthorizationDraft: Sub2APIAuthorizationDraft {
        makeSub2APIAuthorizationDraft(
            baseURL: baseURL,
            accessToken: sub2APIAccessToken,
            refreshToken: sub2APIRefreshToken,
            tokenExpiresAt: sub2APITokenExpiresAt
        )
    }

    private var editProviderSubtitle: String {
        switch providerType {
        case .newapi:
            return "更新站点信息后，可继续在主页同步账号额度、Key 额度和模型。"
        case .cliProxy:
            return "更新 BaseURL 或管理密钥后，可继续同步 API Keys 并刷新模型。"
        case .openAICompatible:
            return "更新名称或 BaseURL 后，可继续手动管理多个 API Key 并刷新模型。"
        case .ccSwitch:
            return "更新数据库路径后，可继续从 CC Switch 本地配置读取 Codex official 账号额度。"
        case .sub2api:
            return "更新 BaseURL 或重新导入登录态后，可继续同步账号余额、Keys 和模型。"
        }
    }
}

private struct AddProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: ModelsBarState
    @State private var providerType: ProviderType
    @State private var name: String
    @State private var baseURL = ""
    @State private var managementToken = ""
    @State private var managementUserID = ""
    @State private var apiKey = ""
    @State private var sub2APIAccessToken = ""
    @State private var sub2APIRefreshToken = ""
    @State private var sub2APITokenExpiresAt = ""
    @State private var sub2APIAuthorization: Sub2APIAuthorizationSession?
    @State private var sub2APIAuthorizedDraft: Sub2APIAuthorizationDraft?
    @State private var saveErrorMessage: String?
    @State private var isAdding = false

    init(providerType: ProviderType) {
        _providerType = State(initialValue: providerType)
        _name = State(initialValue: providerType.defaultProviderName)
        _baseURL = State(initialValue: providerType == .ccSwitch ? CCSwitchCodexAccountService.defaultDatabasePath : "")
    }

    var body: some View {
        ZStack {
            SettingsWindowBackground()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("添加站点")
                        .font(.title3.weight(.semibold))
                    Text(addProviderSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsFieldBlock(title: "站点类型") {
                    ProviderTypePicker(selection: $providerType, isEditable: false)
                }

                SettingsFieldBlock(title: "名称") {
                    SettingsTextField(text: $name, placeholder: providerType.defaultProviderName)
                }

                SettingsFieldBlock(title: providerEndpointFieldTitle(providerType)) {
                    SettingsTextField(
                        text: $baseURL,
                        placeholder: providerEndpointPlaceholder(providerType),
                        monospaced: true,
                        enablesSelection: true
                    )
                }

                if providerType == .newapi || providerType == .cliProxy {
                    SettingsFieldBlock(title: "系统访问令牌") {
                        SettingsTextField(
                            text: $managementToken,
                            placeholder: providerType == .cliProxy ? "Management Key" : "系统访问令牌",
                            monospaced: true,
                            enablesSelection: true
                        )
                    }

                    if providerType == .newapi {
                        SettingsFieldBlock(title: "用户ID") {
                            SettingsTextField(text: $managementUserID, placeholder: "用户ID")
                        }
                    }
                } else if providerType == .openAICompatible {
                    SettingsFieldBlock(title: "API Key") {
                        SettingsTextField(
                            text: $apiKey,
                            placeholder: "sk-... 或其他兼容 Key",
                            monospaced: true,
                            enablesSelection: true
                        )
                    }
                } else if providerType == .ccSwitch {
                    SettingsFieldBlock(title: "说明") {
                        Text("将从本机 CC Switch SQLite 数据库读取 Codex official 登录信息，自定义第三方 Codex Provider 会被跳过。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(SettingsInputBackground())
                    }
                } else {
                    Sub2APIAuthorizationImportSection(
                        accessToken: $sub2APIAccessToken,
                        refreshToken: $sub2APIRefreshToken,
                        tokenExpiresAt: $sub2APITokenExpiresAt,
                        baseURL: baseURL,
                        authorization: sub2APIAuthorization,
                        isCurrentAuthorization: currentSub2APIAuthorizationDraft == sub2APIAuthorizedDraft,
                        errorMessage: saveErrorMessage
                    )
                }

                HStack {
                    SettingsActionButton(title: "取消", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isAdding)

                    Spacer(minLength: 0)

                    SettingsActionButton(title: isAdding ? "添加中" : "添加站点", systemImage: "plus") {
                        isAdding = true
                        saveErrorMessage = nil
                        Task { @MainActor in
                            do {
                                let providerID: UUID
                                switch providerType {
                                case .newapi:
                                    providerID = state.addProvider(
                                        type: providerType,
                                        name: name,
                                        baseURL: baseURL,
                                        managementToken: managementToken,
                                        managementUserID: managementUserID
                                    )
                                case .cliProxy:
                                    providerID = state.addProvider(
                                        type: providerType,
                                        name: name,
                                        baseURL: CLIProxyManagementClient.normalizedBaseURLString(baseURL),
                                        managementToken: managementToken,
                                        managementUserID: ""
                                    )
                                case .openAICompatible:
                                    providerID = state.addOpenAICompatibleProvider(
                                        name: name,
                                        baseURL: baseURL,
                                        apiKey: apiKey
                                    )
                                case .ccSwitch:
                                    providerID = state.addProvider(
                                        type: providerType,
                                        name: name,
                                        baseURL: normalizedBaseURLField(baseURL, providerType: providerType),
                                        managementToken: "",
                                        managementUserID: ""
                                    )
                                case .sub2api:
                                    let validation = try await validateSub2APIAuthorizationDraft(
                                        state: state,
                                        baseURL: baseURL,
                                        accessToken: sub2APIAccessToken,
                                        refreshToken: sub2APIRefreshToken,
                                        tokenExpiresAt: sub2APITokenExpiresAt
                                    )
                                    sub2APIAuthorization = validation.session
                                    sub2APIAuthorizedDraft = validation.draft
                                    providerID = state.addSub2APIProvider(
                                        name: name,
                                        baseURL: baseURL,
                                        authorization: validation.session
                                    )
                                }
                                await state.syncManagedTokens(providerID: providerID)
                                isAdding = false
                                dismiss()
                            } catch {
                                saveErrorMessage = error.localizedDescription
                                isAdding = false
                            }
                        }
                    }
                    .disabled(
                        isAdding || isSaveDisabled
                    )
                }
            }
            .padding(28)
            .frame(width: 520)
        }
    }

    private var isSaveDisabled: Bool {
        let trimmedBaseURL = normalizedBaseURLField(baseURL, providerType: providerType)
        switch providerType {
        case .newapi:
            return trimmedBaseURL.isEmpty ||
                managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                managementUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cliProxy:
            return trimmedBaseURL.isEmpty ||
                managementToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openAICompatible:
            return trimmedBaseURL.isEmpty ||
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ccSwitch:
            return trimmedBaseURL.isEmpty
        case .sub2api:
            return trimmedBaseURL.isEmpty ||
                normalizedSub2APIField(sub2APIAccessToken).isEmpty ||
                normalizedSub2APIField(sub2APIRefreshToken).isEmpty
        }
    }

    private var currentSub2APIAuthorizationDraft: Sub2APIAuthorizationDraft {
        makeSub2APIAuthorizationDraft(
            baseURL: baseURL,
            accessToken: sub2APIAccessToken,
            refreshToken: sub2APIRefreshToken,
            tokenExpiresAt: sub2APITokenExpiresAt
        )
    }

    private var addProviderSubtitle: String {
        switch providerType {
        case .newapi:
            return "保存后会立即同步账号额度、Key 额度和模型。"
        case .cliProxy:
            return "保存后会立即同步 API Keys、Codex 账号额度，并开始刷新模型列表。"
        case .openAICompatible:
            return "保存后会立即添加第一个 API Key，并开始刷新模型列表。"
        case .ccSwitch:
            return "保存后会读取 CC Switch 本地数据库中的 Codex official 账号，并刷新额度。"
        case .sub2api:
            return "保存后会立即同步账号余额、Key 额度和模型。"
        }
    }
}
