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
