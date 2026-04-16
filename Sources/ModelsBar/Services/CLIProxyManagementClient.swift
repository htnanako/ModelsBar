import Foundation

struct CLIProxyManagementClient {
    let baseURLString: String
    let managementKey: String
    var timeout: TimeInterval = 40

    static func normalizedBaseURLString(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return value
        }

        value = value.replacingOccurrences(
            of: #"/?v0/management/?$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)

        if value.hasPrefix("http://") == false && value.hasPrefix("https://") == false {
            value = "http://\(value)"
        }

        return value
    }

    func validateConnection() async throws {
        var request = try managementRequest(path: "config", method: "GET")
        request.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: nil)
    }

    func fetchAPIKeys() async throws -> [String] {
        var request = try managementRequest(path: "api-keys", method: "GET")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try parseAPIKeys(from: data)
    }

    func fetchAuthFiles() async throws -> [CLIProxyAuthFileSummary] {
        var request = try managementRequest(path: "auth-files", method: "GET")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try parseAuthFiles(from: data)
    }

    func downloadAuthFile(named name: String) async throws -> Data {
        var components = URLComponents(url: try managementEndpoint(path: "auth-files/download"), resolvingAgainstBaseURL: false)
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?"))
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        components?.percentEncodedQuery = "name=\(encodedName)"
        guard let url = components?.url else {
            throw CLIProxyManagementClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(managementKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func managementRequest(path: String, method: String) throws -> URLRequest {
        let trimmedKey = managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.isEmpty == false else {
            throw CLIProxyManagementClientError.invalidManagementKey
        }

        var request = URLRequest(url: try managementEndpoint(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func managementEndpoint(path: String) throws -> URL {
        let normalizedBaseURL = Self.normalizedBaseURLString(baseURLString)
        guard let base = URL(string: normalizedBaseURL),
              let scheme = base.scheme,
              scheme.hasPrefix("http") else {
            throw CLIProxyManagementClientError.invalidBaseURL
        }

        return base
            .appending(path: "v0")
            .appending(path: "management")
            .appending(path: path)
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CLIProxyManagementClientError.api("无效的 HTTP 响应")
        }

        guard 200..<300 ~= http.statusCode else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw CLIProxyManagementClientError.httpStatus(http.statusCode, body)
        }
    }

    private func parseAPIKeys(from data: Data) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: data)

        if let dictionary = json as? [String: Any] {
            if let keys = dictionary["api-keys"] as? [Any] {
                return normalizeKeys(keys)
            }

            if let keys = dictionary["apiKeys"] as? [Any] {
                return normalizeKeys(keys)
            }
        }

        if let array = json as? [Any] {
            return normalizeKeys(array)
        }

        throw CLIProxyManagementClientError.api("无法解析 API Keys 响应")
    }

    private func parseAuthFiles(from data: Data) throws -> [CLIProxyAuthFileSummary] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard
            let dictionary = json as? [String: Any],
            let files = dictionary["files"] as? [[String: Any]]
        else {
            throw CLIProxyManagementClientError.api("无法解析 auth-files 响应")
        }

        return files.compactMap { file in
            guard let name = file["name"] as? String else {
                return nil
            }

            return CLIProxyAuthFileSummary(
                id: CLIProxyJSON.stringValue(file["id"]) ?? name,
                name: name,
                provider: CLIProxyJSON.stringValue(file["provider"] ?? file["type"]) ?? "unknown",
                email: CLIProxyJSON.stringValue(file["email"]),
                status: CLIProxyJSON.stringValue(file["status"]),
                statusMessage: CLIProxyJSON.stringValue(file["status_message"] ?? file["statusMessage"]),
                disabled: CLIProxyJSON.boolValue(file["disabled"]),
                unavailable: CLIProxyJSON.boolValue(file["unavailable"]),
                lastRefresh: parseDate(file["last_refresh"] ?? file["lastRefresh"]),
                updatedAt: parseDate(file["updated_at"] ?? file["updatedAt"] ?? file["modtime"])
            )
        }
    }

    private func parseDate(_ value: Any?) -> Date? {
        switch value {
        case let seconds as TimeInterval:
            return Date(timeIntervalSince1970: seconds)
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return nil
            }
            if let seconds = TimeInterval(trimmed) {
                return Date(timeIntervalSince1970: seconds)
            }
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: trimmed)
        default:
            return nil
        }
    }

    private func normalizeKeys(_ keys: [Any]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for entry in keys {
            let value = String(describing: entry).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else {
                continue
            }

            if seen.insert(value).inserted {
                normalized.append(value)
            }
        }

        return normalized
    }
}

struct CLIProxyAuthFileSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var provider: String
    var email: String?
    var status: String?
    var statusMessage: String?
    var disabled: Bool
    var unavailable: Bool
    var lastRefresh: Date?
    var updatedAt: Date?
}

private enum CLIProxyJSON {
    static func stringValue(_ value: Any?) -> String? {
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

    static func boolValue(_ value: Any?) -> Bool {
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
}

enum CLIProxyManagementClientError: LocalizedError {
    case invalidBaseURL
    case invalidManagementKey
    case httpStatus(Int, String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "BaseURL 无效"
        case .invalidManagementKey:
            "管理密钥为空"
        case .httpStatus(let status, let body):
            "HTTP \(status): \(body)"
        case .api(let message):
            message
        }
    }
}
