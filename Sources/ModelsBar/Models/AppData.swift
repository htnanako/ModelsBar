import Foundation

struct AppData: Codable, Equatable {
    var providers: [ProviderConfig] = []
    var modelRecords: [ModelRecord] = []
    var quotaRecords: [QuotaDailyRecord] = []
    var testResults: [ModelTestResult] = []
    var updatedAt: Date = .now
}

enum ProviderType: String, Codable, CaseIterable, Hashable, Identifiable {
    case newapi
    case sub2api
    case cliProxy
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newapi:
            return "NewAPI"
        case .sub2api:
            return "Sub2API"
        case .cliProxy:
            return "CLI Proxy API"
        case .openAICompatible:
            return "OpenAI Compatible"
        }
    }

    var defaultProviderName: String {
        switch self {
        case .newapi: "NewAPI"
        case .sub2api: "Sub2API"
        case .cliProxy: "CLI Proxy API"
        case .openAICompatible: "OpenAI Compatible"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case ProviderType.sub2api.rawValue, "subapi":
            self = .sub2api
        case ProviderType.cliProxy.rawValue, "cli-proxy", "cpa":
            self = .cliProxy
        case ProviderType.openAICompatible.rawValue, "openai-compatible", "openai", "direct":
            self = .openAICompatible
        case ProviderType.newapi.rawValue:
            self = .newapi
        default:
            self = .newapi
        }
    }
}

struct ProviderConfig: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var type: ProviderType
    var name: String
    var baseURL: String
    var managementToken: String?
    var managementUserID: String?
    var accountQuota: AccountQuotaSnapshot?
    var sub2APIAccessToken: String?
    var sub2APIRefreshToken: String?
    var sub2APITokenExpiresAt: Date?
    var sub2APIUser: Sub2APIUserSnapshot?
    var lastStatusMessage: String?
    var requiresManualKeyCompletion: Bool
    var isEnabled: Bool
    var keys: [APIKeyConfig]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: ProviderType = .newapi,
        name: String,
        baseURL: String = "",
        managementToken: String? = nil,
        managementUserID: String? = nil,
        accountQuota: AccountQuotaSnapshot? = nil,
        sub2APIAccessToken: String? = nil,
        sub2APIRefreshToken: String? = nil,
        sub2APITokenExpiresAt: Date? = nil,
        sub2APIUser: Sub2APIUserSnapshot? = nil,
        lastStatusMessage: String? = nil,
        requiresManualKeyCompletion: Bool = false,
        isEnabled: Bool = true,
        keys: [APIKeyConfig] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.baseURL = baseURL
        self.managementToken = managementToken
        self.managementUserID = managementUserID
        self.accountQuota = accountQuota
        self.sub2APIAccessToken = sub2APIAccessToken
        self.sub2APIRefreshToken = sub2APIRefreshToken
        self.sub2APITokenExpiresAt = sub2APITokenExpiresAt
        self.sub2APIUser = sub2APIUser
        self.lastStatusMessage = lastStatusMessage
        self.requiresManualKeyCompletion = requiresManualKeyCompletion
        self.isEnabled = isEnabled
        self.keys = keys
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayBaseURL: String {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBaseURL.isEmpty ? "\(type.title) 暂无配置" : trimmedBaseURL
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case baseURL
        case managementToken
        case managementUserID
        case accountQuota
        case sub2APIAccessToken
        case sub2APIRefreshToken
        case sub2APITokenExpiresAt
        case sub2APIUser
        case lastStatusMessage
        case requiresManualKeyCompletion
        case isEnabled
        case keys
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(ProviderType.self, forKey: .type) ?? .newapi
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? type.defaultProviderName
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        managementToken = try container.decodeIfPresent(String.self, forKey: .managementToken)
        managementUserID = try container.decodeIfPresent(String.self, forKey: .managementUserID)
        accountQuota = try container.decodeIfPresent(AccountQuotaSnapshot.self, forKey: .accountQuota)
        sub2APIAccessToken = try container.decodeIfPresent(String.self, forKey: .sub2APIAccessToken)
        sub2APIRefreshToken = try container.decodeIfPresent(String.self, forKey: .sub2APIRefreshToken)
        sub2APITokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .sub2APITokenExpiresAt)
        sub2APIUser = try container.decodeIfPresent(Sub2APIUserSnapshot.self, forKey: .sub2APIUser)
        lastStatusMessage = try container.decodeIfPresent(String.self, forKey: .lastStatusMessage)
        requiresManualKeyCompletion = try container.decodeIfPresent(Bool.self, forKey: .requiresManualKeyCompletion) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        keys = try container.decodeIfPresent([APIKeyConfig].self, forKey: .keys) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    var sub2APIAuthorized: Bool {
        (sub2APIRefreshToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

struct APIKeyConfig: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var value: String
    var remoteMaskedValue: String?
    var requiresManualCompletion: Bool = false
    var managedTokenID: Int?
    var managedCreatedTime: Int64?
    var managedRemainQuota: Int64?
    var managedUsedQuota: Int64?
    var managedUnlimitedQuota: Bool?
    var managedStatus: Int?
    var managedExpiredTime: Int64?
    var todayUsedQuota: Int64?
    var todayUsedAmountUSD: Double?
    var todayUsageCheckedAt: Date?
    var isEnabled: Bool = true
    var lastStatus: KeyStatus = .unknown
    var lastMessage: String = "尚未检测"
    var lastCheckedAt: Date?
    var lastQuota: TokenUsage?
    var remoteID: Int64?
    var sub2APIStatus: String?
    var sub2APIQuotaLimitUSD: Double?
    var sub2APIQuotaUsedUSD: Double?
    var sub2APIQuotaRemainingUSD: Double?
    var sub2APIExpiresAt: Date?
    var sub2APIUsage: Sub2APIUsageSnapshot?
    var createdAt: Date = .now
    var updatedAt: Date = .now

    var maskedValue: String {
        guard value.count > 12 else {
            return value.isEmpty ? "" : "••••"
        }

        return "\(value.prefix(6))••••\(value.suffix(4))"
    }

    init(
        id: UUID = UUID(),
        name: String,
        value: String,
        remoteMaskedValue: String? = nil,
        requiresManualCompletion: Bool = false,
        managedTokenID: Int? = nil,
        managedCreatedTime: Int64? = nil,
        managedRemainQuota: Int64? = nil,
        managedUsedQuota: Int64? = nil,
        managedUnlimitedQuota: Bool? = nil,
        managedStatus: Int? = nil,
        managedExpiredTime: Int64? = nil,
        todayUsedQuota: Int64? = nil,
        todayUsedAmountUSD: Double? = nil,
        todayUsageCheckedAt: Date? = nil,
        isEnabled: Bool = true,
        lastStatus: KeyStatus = .unknown,
        lastMessage: String = "尚未检测",
        lastCheckedAt: Date? = nil,
        lastQuota: TokenUsage? = nil,
        remoteID: Int64? = nil,
        sub2APIStatus: String? = nil,
        sub2APIQuotaLimitUSD: Double? = nil,
        sub2APIQuotaUsedUSD: Double? = nil,
        sub2APIQuotaRemainingUSD: Double? = nil,
        sub2APIExpiresAt: Date? = nil,
        sub2APIUsage: Sub2APIUsageSnapshot? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.remoteMaskedValue = remoteMaskedValue
        self.requiresManualCompletion = requiresManualCompletion
        self.managedTokenID = managedTokenID
        self.managedCreatedTime = managedCreatedTime
        self.managedRemainQuota = managedRemainQuota
        self.managedUsedQuota = managedUsedQuota
        self.managedUnlimitedQuota = managedUnlimitedQuota
        self.managedStatus = managedStatus
        self.managedExpiredTime = managedExpiredTime
        self.todayUsedQuota = todayUsedQuota
        self.todayUsedAmountUSD = todayUsedAmountUSD
        self.todayUsageCheckedAt = todayUsageCheckedAt
        self.isEnabled = isEnabled
        self.lastStatus = lastStatus
        self.lastMessage = lastMessage
        self.lastCheckedAt = lastCheckedAt
        self.lastQuota = lastQuota
        self.remoteID = remoteID
        self.sub2APIStatus = sub2APIStatus
        self.sub2APIQuotaLimitUSD = sub2APIQuotaLimitUSD
        self.sub2APIQuotaUsedUSD = sub2APIQuotaUsedUSD
        self.sub2APIQuotaRemainingUSD = sub2APIQuotaRemainingUSD
        self.sub2APIExpiresAt = sub2APIExpiresAt
        self.sub2APIUsage = sub2APIUsage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case value
        case remoteMaskedValue
        case requiresManualCompletion
        case managedTokenID
        case managedCreatedTime
        case managedRemainQuota
        case managedUsedQuota
        case managedUnlimitedQuota
        case managedStatus
        case managedExpiredTime
        case todayUsedQuota
        case todayUsedAmountUSD
        case todayUsageCheckedAt
        case isEnabled
        case lastStatus
        case lastMessage
        case lastCheckedAt
        case lastQuota
        case remoteID
        case sub2APIStatus
        case sub2APIQuotaLimitUSD
        case sub2APIQuotaUsedUSD
        case sub2APIQuotaRemainingUSD
        case sub2APIExpiresAt
        case sub2APIUsage
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default Token"
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        remoteMaskedValue = try container.decodeIfPresent(String.self, forKey: .remoteMaskedValue)
        requiresManualCompletion = try container.decodeIfPresent(Bool.self, forKey: .requiresManualCompletion) ?? false
        managedTokenID = try container.decodeIfPresent(Int.self, forKey: .managedTokenID)
        managedCreatedTime = try container.decodeIfPresent(Int64.self, forKey: .managedCreatedTime)
        managedRemainQuota = try container.decodeIfPresent(Int64.self, forKey: .managedRemainQuota)
        managedUsedQuota = try container.decodeIfPresent(Int64.self, forKey: .managedUsedQuota)
        managedUnlimitedQuota = try container.decodeIfPresent(Bool.self, forKey: .managedUnlimitedQuota)
        managedStatus = try container.decodeIfPresent(Int.self, forKey: .managedStatus)
        managedExpiredTime = try container.decodeIfPresent(Int64.self, forKey: .managedExpiredTime)
        todayUsedQuota = try container.decodeIfPresent(Int64.self, forKey: .todayUsedQuota)
        todayUsedAmountUSD = try container.decodeIfPresent(Double.self, forKey: .todayUsedAmountUSD)
        todayUsageCheckedAt = try container.decodeIfPresent(Date.self, forKey: .todayUsageCheckedAt)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastStatus = try container.decodeIfPresent(KeyStatus.self, forKey: .lastStatus) ?? .unknown
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage) ?? "尚未检测"
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastQuota = try container.decodeIfPresent(TokenUsage.self, forKey: .lastQuota)
        remoteID = try container.decodeIfPresent(Int64.self, forKey: .remoteID)
        sub2APIStatus = try container.decodeIfPresent(String.self, forKey: .sub2APIStatus)
        sub2APIQuotaLimitUSD = try container.decodeIfPresent(Double.self, forKey: .sub2APIQuotaLimitUSD)
        sub2APIQuotaUsedUSD = try container.decodeIfPresent(Double.self, forKey: .sub2APIQuotaUsedUSD)
        sub2APIQuotaRemainingUSD = try container.decodeIfPresent(Double.self, forKey: .sub2APIQuotaRemainingUSD)
        sub2APIExpiresAt = try container.decodeIfPresent(Date.self, forKey: .sub2APIExpiresAt)
        sub2APIUsage = try container.decodeIfPresent(Sub2APIUsageSnapshot.self, forKey: .sub2APIUsage)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

struct ManagedToken: Identifiable, Codable, Equatable, Hashable {
    var id: Int
    var name: String
    var key: String
    var createdTime: Int64?
    var status: Int?
    var remainQuota: Int64?
    var usedQuota: Int64?
    var todayUsedQuota: Int64?
    var unlimitedQuota: Bool?
    var expiredTime: Int64?
}

struct AccountQuotaSnapshot: Codable, Equatable, Hashable {
    var username: String?
    var displayName: String?
    var email: String?
    var group: String?
    var quota: Int64
    var usedQuota: Int64
    var requestCount: Int?
    var checkedAt: Date = .now

    var availableDescription: String {
        quota.newAPIQuotaDollarDescription
    }

    var usedDescription: String {
        usedQuota.newAPIQuotaDollarDescription
    }
}

struct Sub2APIUserSnapshot: Codable, Equatable, Hashable {
    var id: Int64
    var email: String
    var username: String
    var role: String?
    var balance: Double
    var status: String?
    var checkedAt: Date = .now

    var availableDescription: String {
        balance.usdDescription
    }

    var displayName: String {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty == false {
            return trimmedUsername
        }

        return email
    }
}

enum KeyStatus: String, Codable, CaseIterable {
    case unknown
    case healthy
    case warning
    case failed
    case disabled

    var title: String {
        switch self {
        case .unknown: "未检测"
        case .healthy: "正常"
        case .warning: "需注意"
        case .failed: "失败"
        case .disabled: "已停用"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .disabled: "pause.circle"
        }
    }
}

struct ModelRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var providerID: UUID
    var keyID: UUID
    var modelID: String
    var refreshedAt: Date = .now
    var streamResult: ModelTestResult?
    var nonStreamResult: ModelTestResult?
}

struct ModelTestResult: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var providerID: UUID
    var keyID: UUID
    var modelID: String
    var mode: TestMode
    var interface: OpenAIModelInterface
    var succeeded: Bool
    var latencyMS: Int
    var message: String
    var testedAt: Date = .now

    init(
        id: UUID = UUID(),
        providerID: UUID,
        keyID: UUID,
        modelID: String,
        mode: TestMode,
        interface: OpenAIModelInterface,
        succeeded: Bool,
        latencyMS: Int,
        message: String,
        testedAt: Date = .now
    ) {
        self.id = id
        self.providerID = providerID
        self.keyID = keyID
        self.modelID = modelID
        self.mode = mode
        self.interface = interface
        self.succeeded = succeeded
        self.latencyMS = latencyMS
        self.message = message
        self.testedAt = testedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case providerID
        case keyID
        case modelID
        case mode
        case interface
        case succeeded
        case latencyMS
        case message
        case testedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        providerID = try container.decode(UUID.self, forKey: .providerID)
        keyID = try container.decode(UUID.self, forKey: .keyID)
        modelID = try container.decode(String.self, forKey: .modelID)
        mode = try container.decode(TestMode.self, forKey: .mode)
        interface = try container.decodeIfPresent(OpenAIModelInterface.self, forKey: .interface)
            ?? OpenAIModelInterface.recommended(for: modelID)
        succeeded = try container.decode(Bool.self, forKey: .succeeded)
        latencyMS = try container.decode(Int.self, forKey: .latencyMS)
        message = try container.decode(String.self, forKey: .message)
        testedAt = try container.decodeIfPresent(Date.self, forKey: .testedAt) ?? .now
    }
}

enum TestMode: String, Codable, CaseIterable, Hashable {
    case stream
    case nonStream

    var title: String {
        switch self {
        case .stream: "流式"
        case .nonStream: "非流式"
        }
    }
}

struct QuotaDailyRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var providerID: UUID
    var keyID: UUID
    var day: String
    var usage: TokenUsage
    var rawJSON: String
    var recordedAt: Date = .now
}

struct TokenUsage: Codable, Equatable, Hashable {
    var object: String
    var name: String
    var totalGranted: Int64
    var totalUsed: Int64
    var totalAvailable: Int64
    var unlimitedQuota: Bool
    var modelLimits: [String: Bool]
    var modelLimitsEnabled: Bool
    var expiresAt: Int64
}

extension TokenUsage {
    var availableDescription: String {
        unlimitedQuota ? "无限额度" : totalAvailable.newAPIQuotaDollarDescription
    }

    var usedDescription: String {
        totalUsed.newAPIQuotaDollarDescription
    }

    var grantedDescription: String {
        unlimitedQuota ? "无限" : totalGranted.newAPIQuotaDollarDescription
    }
}

extension ProviderConfig {
    var manualCompletionRequiredCount: Int {
        keys.filter(\.requiresManualCompletion).count
    }

    var accountAvailableDescription: String {
        switch type {
        case .newapi:
            return accountQuota?.availableDescription ?? "--"
        case .sub2api:
            return sub2APIUser?.availableDescription ?? "--"
        case .cliProxy:
            return "--"
        case .openAICompatible:
            return "--"
        }
    }

    var totalTodayUsageDescription: String {
        switch type {
        case .newapi:
            let values = keys.compactMap(\.todayUsedQuota)
            guard values.isEmpty == false else {
                return "--"
            }
            return values.reduce(0, +).newAPIQuotaDollarDescription

        case .sub2api:
            let values = keys.compactMap(\.todayUsedAmountUSD)
            guard values.isEmpty == false else {
                return "--"
            }
            return values.reduce(0, +).usdDescription
        case .cliProxy:
            return "--"
        case .openAICompatible:
            return "--"
        }
    }
}

struct Sub2APIUsageSnapshot: Codable, Equatable, Hashable {
    var mode: String
    var isValid: Bool
    var status: String?
    var unit: String
    var planName: String?
    var remaining: Double?
    var balance: Double?
    var quotaLimitUSD: Double?
    var quotaUsedUSD: Double?
    var quotaRemainingUSD: Double?
    var todayUsedAmountUSD: Double?
    var totalUsedAmountUSD: Double?
    var checkedAt: Date = .now

    var isUnlimited: Bool {
        if let quotaRemainingUSD, quotaRemainingUSD < 0 {
            return true
        }

        if let remaining, remaining < 0 {
            return true
        }

        return false
    }

    var availableDescription: String {
        if isUnlimited {
            return "无限"
        }

        if let quotaRemainingUSD {
            return quotaRemainingUSD.usdDescription
        }

        if let remaining {
            return remaining.usdDescription
        }

        if let balance {
            return balance.usdDescription
        }

        return "--"
    }

    var todayDescription: String {
        todayUsedAmountUSD?.usdDescription ?? "--"
    }
}

extension Int64 {
    var newAPIQuotaDollarDescription: String {
        let dollars = Double(self) / 500_000
        if dollars < 0.01 && dollars > 0 {
            return String(format: "$%.4f", dollars)
        }

        return String(format: "$%.2f", dollars)
    }
}

extension Double {
    var usdDescription: String {
        if abs(self) < 0.01 && self != 0 {
            return String(format: "$%.4f", self)
        }

        return String(format: "$%.2f", self)
    }
}

extension APIKeyConfig {
    private var newAPINormalizedValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-") else {
            return trimmed
        }
        return String(trimmed.dropFirst(3))
    }

    private var maskedRemoteDisplayValue: String {
        let masked = (remoteMaskedValue ?? value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard masked.isEmpty == false else {
            return ""
        }
        return masked.hasPrefix("sk-") ? masked : "sk-\(masked)"
    }

    var hasUsableValueForNewAPI: Bool {
        let trimmed = newAPINormalizedValue
        return trimmed.isEmpty == false && trimmed.isMaskedTokenValue == false
    }

    func requestValue(for providerType: ProviderType) -> String? {
        switch providerType {
        case .newapi:
            return hasUsableValueForNewAPI ? newAPINormalizedValue : nil
        case .sub2api:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .cliProxy:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .openAICompatible:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func displayValue(for providerType: ProviderType) -> String {
        switch providerType {
        case .newapi:
            if hasUsableValueForNewAPI {
                return "sk-\(newAPINormalizedValue)"
            }
            return maskedRemoteDisplayValue
        case .sub2api:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .cliProxy:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAICompatible:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func maskedValue(for providerType: ProviderType) -> String {
        let displayValue = displayValue(for: providerType)
        if providerType == .newapi && hasUsableValueForNewAPI == false {
            return displayValue
        }
        guard displayValue.count > 12 else {
            if displayValue.hasPrefix("sk-") {
                return "sk-••••"
            }
            return displayValue.isEmpty ? "" : "••••"
        }

        return "\(displayValue.prefix(6))••••\(displayValue.suffix(4))"
    }

    func availableDescription(for providerType: ProviderType) -> String {
        switch providerType {
        case .newapi:
            if lastQuota?.unlimitedQuota == true || managedUnlimitedQuota == true {
                return "无限"
            }

            if let quota = lastQuota {
                return quota.totalAvailable.newAPIQuotaDollarDescription
            }

            if let managedRemainQuota {
                return managedRemainQuota.newAPIQuotaDollarDescription
            }

            return "--"

        case .sub2api:
            if sub2APIUsage?.isUnlimited == true {
                return "无限"
            }

            if let usage = sub2APIUsage {
                return usage.availableDescription
            }

            if let sub2APIQuotaRemainingUSD {
                return sub2APIQuotaRemainingUSD.usdDescription
            }

            if let sub2APIQuotaLimitUSD, sub2APIQuotaLimitUSD == 0 {
                return "无限"
            }

            return "--"
        case .cliProxy:
            return "--"
        case .openAICompatible:
            return "--"
        }
    }

    func todayUsageDescription(for providerType: ProviderType) -> String {
        switch providerType {
        case .newapi:
            return todayUsedQuota.map(\.newAPIQuotaDollarDescription) ?? "--"
        case .sub2api:
            return todayUsedAmountUSD?.usdDescription ?? sub2APIUsage?.todayDescription ?? "--"
        case .cliProxy:
            return "--"
        case .openAICompatible:
            return "--"
        }
    }

    func quotaSummary(for providerType: ProviderType) -> String {
        switch providerType {
        case .newapi:
            if lastQuota?.unlimitedQuota == true || managedUnlimitedQuota == true {
                return "无限额度"
            }

            if let quota = lastQuota {
                return "\(quota.totalAvailable.newAPIQuotaDollarDescription) / \(quota.totalGranted.newAPIQuotaDollarDescription)"
            }

            if let remain = managedRemainQuota,
               let used = managedUsedQuota {
                let total = remain + used
                guard total > 0 else {
                    return remain.newAPIQuotaDollarDescription
                }
                return "\(remain.newAPIQuotaDollarDescription) / \(total.newAPIQuotaDollarDescription)"
            }

            return "--"

        case .sub2api:
            if sub2APIUsage?.isUnlimited == true {
                return "无限额度"
            }

            if let remaining = sub2APIUsage?.quotaRemainingUSD ?? sub2APIQuotaRemainingUSD,
               let limit = sub2APIUsage?.quotaLimitUSD ?? sub2APIQuotaLimitUSD,
               limit > 0 {
                return "\(remaining.usdDescription) / \(limit.usdDescription)"
            }

            if let remaining = sub2APIUsage?.remaining ?? sub2APIUsage?.balance ?? sub2APIQuotaRemainingUSD {
                return "\(remaining.usdDescription) 可用"
            }

            return "--"
        case .cliProxy:
            return "--"
        case .openAICompatible:
            return "--"
        }
    }

    func quotaProgress(for providerType: ProviderType) -> Double {
        switch providerType {
        case .newapi:
            if lastQuota?.unlimitedQuota == true || managedUnlimitedQuota == true {
                return 1
            }

            if let quota = lastQuota, quota.totalGranted > 0 {
                let ratio = Double(quota.totalAvailable) / Double(quota.totalGranted)
                return min(max(ratio, 0), 1)
            }

            if let remain = managedRemainQuota,
               let used = managedUsedQuota {
                let total = remain + used
                guard total > 0 else {
                    return 0
                }
                return min(max(Double(remain) / Double(total), 0), 1)
            }

            return 0

        case .sub2api:
            if sub2APIUsage?.isUnlimited == true {
                return 1
            }

            if let remaining = sub2APIUsage?.quotaRemainingUSD ?? sub2APIQuotaRemainingUSD,
               let limit = sub2APIUsage?.quotaLimitUSD ?? sub2APIQuotaLimitUSD,
               limit > 0 {
                return min(max(remaining / limit, 0), 1)
            }

            if sub2APIUsage?.remaining != nil || sub2APIUsage?.balance != nil {
                return 1
            }

            return 0
        case .cliProxy:
            return 0
        case .openAICompatible:
            return 0
        }
    }
}

private extension String {
    var isMaskedTokenValue: Bool {
        contains("*") || contains("•")
    }
}
