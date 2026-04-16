import Foundation

struct CodexAuthFilePayload: Hashable {
    var name: String
    var provider: String
    var status: String?
    var statusMessage: String?
    var disabled: Bool
    var unavailable: Bool
    var lastRefresh: Date?
    var data: Data
}

struct CodexAccountQuotaService {
    private let endpointCandidates = [
        "https://chatgpt.com/backend-api/wham/usage",
        "https://chatgpt.com/backend-api/api/codex/usage",
        "https://chatgpt.com/api/codex/usage",
        "https://chatgpt.com/backend-api/codex/usage"
    ]

    func refreshAccounts(from authFiles: [CodexAuthFilePayload]) async -> [CodexAccountSnapshot] {
        var accounts: [CodexAccountSnapshot] = []

        for authFile in authFiles where authFile.provider.caseInsensitiveCompare("codex") == .orderedSame {
            guard let credential = credential(from: authFile) else {
                continue
            }

            var status = deriveBaseStatus(disabled: authFile.disabled, unavailable: authFile.unavailable)
            var statusMessage = authFile.statusMessage
            var fiveHourQuota: CodexQuotaSnapshot?
            var weeklyQuota: CodexQuotaSnapshot?
            var quotaCheckedAt: Date?
            var resolvedEmail = credential.email
            var resolvedPlanType = credential.planType
            var resolvedAccountID = credential.accountID

            if authFile.disabled == false, authFile.unavailable == false {
                do {
                    let usage = try await fetchUsage(for: credential)
                    fiveHourQuota = usage.fiveHourQuota
                    weeklyQuota = usage.weeklyQuota
                    quotaCheckedAt = .now
                    resolvedEmail = usage.email ?? resolvedEmail
                    resolvedPlanType = usage.planType ?? resolvedPlanType
                    resolvedAccountID = usage.accountID ?? resolvedAccountID
                    status = deriveQuotaStatus(
                        fallback: status,
                        fiveHourQuota: fiveHourQuota,
                        weeklyQuota: weeklyQuota
                    )
                    if let usageMessage = usage.message, usageMessage.isEmpty == false {
                        statusMessage = usageMessage
                    }
                } catch {
                    quotaCheckedAt = .now
                    if statusMessage?.isEmpty ?? true {
                        statusMessage = error.localizedDescription
                    }
                }
            }

            accounts.append(
                CodexAccountSnapshot(
                    id: resolvedAccountID ?? resolvedEmail,
                    fileName: authFile.name,
                    email: resolvedEmail,
                    planType: resolvedPlanType,
                    accountID: resolvedAccountID,
                    disabled: authFile.disabled,
                    unavailable: authFile.unavailable,
                    status: status,
                    statusMessage: statusMessage,
                    authRefreshedAt: authFile.lastRefresh ?? credential.lastRefresh,
                    quotaCheckedAt: quotaCheckedAt,
                    fiveHourQuota: fiveHourQuota,
                    weeklyQuota: weeklyQuota
                )
            )
        }

        return accounts.sorted {
            if $0.email != $1.email {
                return $0.email.localizedStandardCompare($1.email) == .orderedAscending
            }
            return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    private func credential(from authFile: CodexAuthFilePayload) -> CodexCredential? {
        guard
            let object = try? JSONSerialization.jsonObject(with: authFile.data) as? [String: Any]
        else {
            return nil
        }

        let normalizedObject: [String: Any]
        if let tokens = object["tokens"] as? [String: Any] {
            normalizedObject = tokens.merging(object) { current, _ in current }
        } else {
            normalizedObject = object
        }

        guard
            let accessToken = stringValue(normalizedObject["access_token"]),
            let idToken = stringValue(normalizedObject["id_token"])
        else {
            return nil
        }

        let claims = decodeJWTClaims(idToken)
        let authInfo = claims?["https://api.openai.com/auth"] as? [String: Any]
        let accountID = stringValue(normalizedObject["account_id"])
            ?? stringValue(authInfo?["chatgpt_account_id"])
        let email = stringValue(normalizedObject["email"])
            ?? stringValue(claims?["email"])
            ?? authFile.name
        let planType = stringValue(authInfo?["chatgpt_plan_type"])
        let lastRefresh = parseDate(normalizedObject["last_refresh"])

        return CodexCredential(
            id: accountID ?? email,
            accessToken: accessToken,
            accountID: accountID,
            email: email,
            planType: planType,
            lastRefresh: lastRefresh
        )
    }

    private func fetchUsage(for credential: CodexCredential) async throws -> CodexUsagePayload {
        let session = URLSession(configuration: .ephemeral)
        var lastError: Error?

        for endpoint in endpointCandidates {
            do {
                return try await fetchUsage(for: credential, endpoint: endpoint, session: session)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CodexAccountQuotaServiceError.usageUnavailable("无法读取 Codex 额度")
    }

    private func fetchUsage(
        for credential: CodexCredential,
        endpoint: String,
        session: URLSession
    ) async throws -> CodexUsagePayload {
        guard let url = URL(string: endpoint) else {
            throw CodexAccountQuotaServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/codex", forHTTPHeaderField: "Referer")
        request.setValue("codex_cli_rs/0.119.0 (Mac OS; arm64) vscode/1.99.3", forHTTPHeaderField: "User-Agent")
        if let accountID = credential.accountID, accountID.isEmpty == false {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexAccountQuotaServiceError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            if body.contains("<html") {
                throw CodexAccountQuotaServiceError.cloudflareChallenge
            }
            throw CodexAccountQuotaServiceError.httpStatus(http.statusCode, body)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if let payload = parseWHAMUsagePayload(from: object) {
            return payload
        }

        let message = extractMessage(from: object)
        let windows = collectQuotaWindows(from: object)

        return CodexUsagePayload(
            fiveHourQuota: bestQuotaWindow(near: 300, from: windows),
            weeklyQuota: bestQuotaWindow(near: 10_080, from: windows),
            message: message
        )
    }

    private func parseWHAMUsagePayload(from object: Any) -> CodexUsagePayload? {
        guard
            let dictionary = object as? [String: Any],
            let rateLimit = dictionary["rate_limit"] as? [String: Any]
        else {
            return nil
        }

        let primary = quotaWindowFromWHAM(
            rateLimit["primary_window"] as? [String: Any],
            fallbackWindowSeconds: 18_000
        )
        let secondary = quotaWindowFromWHAM(
            rateLimit["secondary_window"] as? [String: Any],
            fallbackWindowSeconds: 604_800
        )

        guard primary != nil || secondary != nil else {
            return nil
        }

        let allowed = boolValue(rateLimit["allowed"])
        let limitReached = boolValue(rateLimit["limit_reached"])
        let message: String?
        if limitReached {
            message = "额度已用尽"
        } else if allowed == false {
            message = "当前账号暂不可用"
        } else {
            message = extractMessage(from: object)
        }

        return CodexUsagePayload(
            email: stringValue(dictionary["email"]),
            accountID: stringValue(dictionary["account_id"]),
            planType: stringValue(dictionary["plan_type"]),
            fiveHourQuota: primary,
            weeklyQuota: secondary,
            message: message
        )
    }

    private func quotaWindowFromWHAM(
        _ dictionary: [String: Any]?,
        fallbackWindowSeconds: Int
    ) -> CodexQuotaSnapshot? {
        guard let dictionary else {
            return nil
        }

        let windowSeconds = intValue(dictionary["limit_window_seconds"]) ?? fallbackWindowSeconds
        let usedPercent = intValue(dictionary["used_percent"])
        let resetsAt = parseDate(dictionary["reset_at"])

        guard usedPercent != nil || resetsAt != nil else {
            return nil
        }

        return CodexQuotaSnapshot(
            windowMinutes: max(windowSeconds / 60, 1),
            limit: nil,
            used: nil,
            remaining: nil,
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    private func collectQuotaWindows(from object: Any) -> [CodexQuotaSnapshot] {
        switch object {
        case let dictionary as [String: Any]:
            var windows: [CodexQuotaSnapshot] = []
            if let window = quotaWindow(from: dictionary) {
                windows.append(window)
            }
            for value in dictionary.values {
                windows.append(contentsOf: collectQuotaWindows(from: value))
            }
            return windows

        case let array as [Any]:
            return array.flatMap { collectQuotaWindows(from: $0) }

        default:
            return []
        }
    }

    private func quotaWindow(from dictionary: [String: Any]) -> CodexQuotaSnapshot? {
        let windowMinutes = intValue(
            dictionary["windowDurationMins"]
                ?? dictionary["window_duration_mins"]
                ?? dictionary["windowMinutes"]
                ?? dictionary["window_minutes"]
                ?? dictionary["window_duration_minutes"]
        )

        let limit = intValue(dictionary["limit"] ?? dictionary["max"] ?? dictionary["quota"])
        var used = intValue(dictionary["used"] ?? dictionary["usage"] ?? dictionary["count"] ?? dictionary["consumed"])
        var remaining = intValue(
            dictionary["remaining"]
                ?? dictionary["remainingCount"]
                ?? dictionary["remaining_count"]
                ?? dictionary["available"]
        )

        if remaining == nil, let limit, let used {
            remaining = max(limit - used, 0)
        }
        if used == nil, let limit, let remaining {
            used = max(limit - remaining, 0)
        }

        let resetsAt = parseDate(
            dictionary["resetsAt"]
                ?? dictionary["resetAt"]
                ?? dictionary["reset_at"]
                ?? dictionary["nextResetAt"]
        )

        guard windowMinutes != nil || limit != nil || used != nil || remaining != nil else {
            return nil
        }

        return CodexQuotaSnapshot(
            windowMinutes: windowMinutes ?? inferredWindowMinutes(limit: limit, remaining: remaining),
            limit: limit,
            used: used,
            remaining: remaining,
            usedPercent: nil,
            resetsAt: resetsAt
        )
    }

    private func inferredWindowMinutes(limit: Int?, remaining: Int?) -> Int {
        if let limit, limit <= 400 {
            return 300
        }
        if let remaining, remaining <= 400 {
            return 300
        }
        return 10_080
    }

    private func bestQuotaWindow(near target: Int, from windows: [CodexQuotaSnapshot]) -> CodexQuotaSnapshot? {
        windows.min { lhs, rhs in
            let lhsDistance = abs(lhs.windowMinutes - target)
            let rhsDistance = abs(rhs.windowMinutes - target)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            let lhsCompleteness = completenessScore(lhs)
            let rhsCompleteness = completenessScore(rhs)
            if lhsCompleteness != rhsCompleteness {
                return lhsCompleteness > rhsCompleteness
            }

            return lhs.windowMinutes < rhs.windowMinutes
        }
    }

    private func completenessScore(_ quota: CodexQuotaSnapshot) -> Int {
        [quota.limit, quota.used, quota.remaining, quota.usedPercent].compactMap { $0 }.count
    }

    private func deriveBaseStatus(disabled: Bool, unavailable: Bool) -> KeyStatus {
        if disabled {
            return .disabled
        }
        if unavailable {
            return .warning
        }
        return .unknown
    }

    private func deriveQuotaStatus(
        fallback: KeyStatus,
        fiveHourQuota: CodexQuotaSnapshot?,
        weeklyQuota: CodexQuotaSnapshot?
    ) -> KeyStatus {
        let windows = [fiveHourQuota, weeklyQuota].compactMap { $0 }
        guard windows.isEmpty == false else {
            return fallback
        }

        if windows.contains(where: { ($0.progressValue ?? 1) <= 0 }) {
            return .exhausted
        }

        if windows.contains(where: { ($0.progressValue ?? 1) < 0.15 }) {
            return .warning
        }

        return .healthy
    }

    private func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }

        var payload = String(parts[1])
        switch payload.count % 4 {
        case 2:
            payload += "=="
        case 3:
            payload += "="
        default:
            break
        }

        guard
            let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private func extractMessage(from object: Any) -> String? {
        switch object {
        case let dictionary as [String: Any]:
            for key in ["message", "detail", "error", "status_message"] {
                if let value = stringValue(dictionary[key]), value.isEmpty == false {
                    return value
                }
            }
            for value in dictionary.values {
                if let nested = extractMessage(from: value), nested.isEmpty == false {
                    return nested
                }
            }
            return nil

        case let array as [Any]:
            for value in array {
                if let nested = extractMessage(from: value), nested.isEmpty == false {
                    return nested
                }
            }
            return nil

        default:
            return nil
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    private func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "true", "yes"].contains(string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        default:
            return false
        }
    }

    private func parseDate(_ value: Any?) -> Date? {
        switch value {
        case let date as Date:
            return date
        case let seconds as Int:
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        case let seconds as Int64:
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        case let seconds as Double:
            return Date(timeIntervalSince1970: seconds)
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return nil
            }
            if let seconds = Double(trimmed) {
                return Date(timeIntervalSince1970: seconds)
            }
            let iso8601Formatter = ISO8601DateFormatter()
            if let date = iso8601Formatter.date(from: trimmed) {
                return date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
            return formatter.date(from: trimmed)
        default:
            return nil
        }
    }
}

private struct CodexCredential {
    var id: String
    var accessToken: String
    var accountID: String?
    var email: String
    var planType: String?
    var lastRefresh: Date?
}

private struct CodexUsagePayload {
    var email: String?
    var accountID: String?
    var planType: String?
    var fiveHourQuota: CodexQuotaSnapshot?
    var weeklyQuota: CodexQuotaSnapshot?
    var message: String?
}

private enum CodexAccountQuotaServiceError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case cloudflareChallenge
    case httpStatus(Int, String)
    case usageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Codex 额度接口无效"
        case .invalidResponse:
            return "Codex 额度响应无效"
        case .cloudflareChallenge:
            return "ChatGPT 官方接口返回挑战页，当前无法直接读取额度"
        case .httpStatus(let status, let body):
            return "Codex 额度接口返回 HTTP \(status): \(body)"
        case .usageUnavailable(let message):
            return message
        }
    }
}
