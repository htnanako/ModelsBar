import Foundation

struct Sub2APIClient {
    let baseURLString: String
    var timeout: TimeInterval = 40

    func refreshAuth(refreshToken: String) async throws -> Sub2APITokenPair {
        let trimmedToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.isEmpty == false else {
            throw Sub2APIClientError.authorizationRequired
        }

        var request = try request(url: managementEndpoint(path: "auth/refresh"), method: "POST")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(Sub2APIRefreshRequest(refreshToken: trimmedToken))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateManagementResponse(response: response, data: data)
        return try decodeEnvelope(Sub2APITokenPair.self, from: data)
    }

    func fetchCurrentUser(accessToken: String) async throws -> Sub2APIUserSnapshot {
        var request = try authorizedManagementRequest(
            url: managementEndpoint(path: "user/profile"),
            method: "GET",
            accessToken: accessToken
        )
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateManagementResponse(response: response, data: data)
        let decoded = try decodeEnvelope(Sub2APIUserResponse.self, from: data)
        return decoded.snapshot
    }

    func fetchManagedKeys(accessToken: String) async throws -> [Sub2APIManagedKey] {
        var page = 1
        let pageSize = 1_000
        var collected: [Sub2APIManagedKey] = []
        var totalPages = 1

        repeat {
            var components = URLComponents(url: try managementEndpoint(path: "keys"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
                URLQueryItem(name: "sort_by", value: "created_at"),
                URLQueryItem(name: "sort_order", value: "desc")
            ]

            guard let url = components?.url else {
                throw Sub2APIClientError.invalidBaseURL
            }

            var request = try authorizedManagementRequest(url: url, method: "GET", accessToken: accessToken)
            request.timeoutInterval = timeout

            let (data, response) = try await URLSession.shared.data(for: request)
            try validateManagementResponse(response: response, data: data)
            let decoded = try decodeEnvelope(Sub2APIPaginatedResponse<Sub2APIManagedKeyResponse>.self, from: data)

            collected.append(contentsOf: decoded.items.map(\.managedKey))
            totalPages = max(decoded.pages, 1)
            page += 1
        } while page <= totalPages

        return collected
    }

    func fetchKeyUsage(apiKey: String) async throws -> Sub2APIUsageFetchResult {
        var request = try authorizedGatewayRequest(url: gatewayEndpoint(path: "usage"), method: "GET", apiKey: apiKey)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateGatewayResponse(response: response, data: data)

        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw Sub2APIClientError.api("无法解析 Key 用量响应")
        }

        let quota = dictionary["quota"] as? [String: Any]
        let usage = dictionary["usage"] as? [String: Any]
        let today = usage?["today"] as? [String: Any]
        let total = usage?["total"] as? [String: Any]
        let remaining = Sub2APIJSON.doubleValue(dictionary["remaining"] ?? quota?["remaining"] ?? dictionary["balance"])
        let unit = Sub2APIJSON.stringValue(dictionary["unit"] ?? quota?["unit"]) ?? "USD"

        let snapshot = Sub2APIUsageSnapshot(
            mode: Sub2APIJSON.stringValue(dictionary["mode"]) ?? "unknown",
            isValid: Sub2APIJSON.boolValue(dictionary["isValid"] ?? dictionary["is_valid"]) ?? true,
            status: Sub2APIJSON.stringValue(dictionary["status"]),
            unit: unit,
            planName: Sub2APIJSON.stringValue(dictionary["planName"] ?? dictionary["plan_name"]),
            remaining: remaining,
            balance: Sub2APIJSON.doubleValue(dictionary["balance"]),
            quotaLimitUSD: Sub2APIJSON.doubleValue(quota?["limit"]),
            quotaUsedUSD: Sub2APIJSON.doubleValue(quota?["used"]),
            quotaRemainingUSD: Sub2APIJSON.doubleValue(quota?["remaining"]),
            todayUsedAmountUSD: Sub2APIJSON.doubleValue(today?["actual_cost"] ?? today?["cost"]),
            totalUsedAmountUSD: Sub2APIJSON.doubleValue(total?["actual_cost"] ?? total?["cost"])
        )

        return Sub2APIUsageFetchResult(
            usage: snapshot,
            rawJSON: String(data: data, encoding: .utf8) ?? "{}"
        )
    }

    private func request(url: URL, method: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func authorizedManagementRequest(url: URL, method: String, accessToken: String) throws -> URLRequest {
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.isEmpty == false else {
            throw Sub2APIClientError.authorizationRequired
        }

        var request = try request(url: url, method: method)
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func authorizedGatewayRequest(url: URL, method: String, apiKey: String) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw Sub2APIClientError.invalidAPIKey
        }

        var request = try request(url: url, method: method)
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func managementEndpoint(path: String) throws -> URL {
        var base = try managementBaseURL()
        for component in path.split(separator: "/") {
            base.append(path: String(component))
        }
        return base
    }

    private func gatewayEndpoint(path: String) throws -> URL {
        var base = try gatewayBaseURL()

        for component in path.split(separator: "/") {
            base.append(path: String(component))
        }

        return base
    }

    private func managementBaseURL() throws -> URL {
        try rootBaseURL()
            .appending(path: "api")
            .appending(path: "v1")
    }

    private func gatewayBaseURL() throws -> URL {
        try rootBaseURL().appending(path: "v1")
    }

    private func rootBaseURL() throws -> URL {
        var base = try parsedBaseURL()
        let pathParts = base.path.split(separator: "/").map(String.init)

        if pathParts.count >= 2,
           pathParts[pathParts.count - 2] == "api",
           pathParts.last == "v1" {
            base.deleteLastPathComponent()
            base.deleteLastPathComponent()
            return base
        }

        if pathParts.last == "v1" {
            base.deleteLastPathComponent()
        }

        return base
    }

    private func parsedBaseURL() throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") else {
            throw Sub2APIClientError.invalidBaseURL
        }
        return url
    }

    private func validateManagementResponse(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw Sub2APIClientError.api("无效的 HTTP 响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw Sub2APIClientError.authorizationRequired
        }

        guard 200..<300 ~= http.statusCode else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw Sub2APIClientError.httpStatus(http.statusCode, body)
        }
    }

    private func validateGatewayResponse(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw Sub2APIClientError.api("无效的 HTTP 响应")
        }

        guard 200..<300 ~= http.statusCode else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw Sub2APIClientError.httpStatus(http.statusCode, body)
        }
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Sub2APIEnvelope<T>.self, from: data)
        guard envelope.code == 0 else {
            throw Sub2APIClientError.api(envelope.message)
        }

        guard let value = envelope.data else {
            throw Sub2APIClientError.api("响应缺少 data")
        }

        return value
    }
}

struct Sub2APITokenPair: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }

    var tokenExpiresAt: Date? {
        guard expiresIn > 0 else {
            return nil
        }

        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

struct Sub2APIManagedKey: Equatable {
    var id: Int64
    var key: String
    var name: String
    var status: String
    var quotaLimitUSD: Double
    var quotaUsedUSD: Double
    var expiresAt: Date?
}

struct Sub2APIUsageFetchResult: Equatable {
    var usage: Sub2APIUsageSnapshot
    var rawJSON: String
}

struct Sub2APIAuthorizationSession: Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenExpiresAt: Date?
    var user: Sub2APIUserSnapshot
}

enum Sub2APIClientError: LocalizedError {
    case invalidBaseURL
    case invalidAPIKey
    case authorizationRequired
    case httpStatus(Int, String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "BaseURL 无效"
        case .invalidAPIKey:
            "ApiKey 为空"
        case .authorizationRequired:
            "请重新导入登录态"
        case .httpStatus(let status, let body):
            "HTTP \(status): \(body)"
        case .api(let message):
            message
        }
    }
}

private struct Sub2APIEnvelope<T: Decodable>: Decodable {
    var code: Int
    var message: String
    var data: T?
}

private struct Sub2APIRefreshRequest: Encodable {
    var refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct Sub2APIPaginatedResponse<T: Decodable>: Decodable {
    var items: [T]
    var total: Int64
    var page: Int
    var pageSize: Int
    var pages: Int

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case pageSize = "page_size"
        case pages
    }
}

private struct Sub2APIUserResponse: Decodable {
    var id: Int64
    var email: String
    var username: String
    var role: String?
    var balance: Double
    var status: String?

    var snapshot: Sub2APIUserSnapshot {
        Sub2APIUserSnapshot(
            id: id,
            email: email,
            username: username,
            role: role,
            balance: balance,
            status: status
        )
    }
}

private struct Sub2APIManagedKeyResponse: Decodable {
    var id: Int64
    var key: String
    var name: String
    var status: String
    var quota: Double
    var quotaUsed: Double
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case name
        case status
        case quota
        case quotaUsed = "quota_used"
        case expiresAt = "expires_at"
    }

    var managedKey: Sub2APIManagedKey {
        Sub2APIManagedKey(
            id: id,
            key: key,
            name: name,
            status: status,
            quotaLimitUSD: quota,
            quotaUsedUSD: quotaUsed,
            expiresAt: expiresAt
        )
    }
}

private enum Sub2APIJSON {
    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let int64 = value as? Int64 {
            return Double(int64)
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }
}
