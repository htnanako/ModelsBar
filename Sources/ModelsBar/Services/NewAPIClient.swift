import Foundation

struct NewAPIClient {
    let baseURLString: String
    let apiKey: String
    var timeout: TimeInterval = 40

    func fetchModels() async throws -> [String] {
        var request = try authorizedRequest(url: openAIEndpoint(path: "models"), method: "GET")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    func fetchTokenUsage() async throws -> TokenUsageFetchResult {
        var request = try authorizedRequest(url: usageEndpoint(), method: "GET")
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(NewAPIUsageResponse.self, from: data)
        guard decoded.code else {
            throw NewAPIClientError.api(decoded.message)
        }

        let raw = String(data: data, encoding: .utf8) ?? "{}"
        return TokenUsageFetchResult(usage: decoded.data.tokenUsage, rawJSON: raw)
    }

    func fetchManagedTokens(accessToken: String, userID: String?) async throws -> [ManagedToken] {
        var request = try managementRequest(
            url: tokenManagementEndpoint(),
            method: "GET",
            accessToken: accessToken,
            userID: userID
        )
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        var tokens = try parseManagedTokens(from: data)
        let fullKeys = try await fetchAllManagedTokenKeys(
            accessToken: accessToken,
            userID: userID,
            tokens: tokens
        )
        tokens = tokens.map { token in
            var token = token
            if let fullKey = fullKeys[token.id], fullKey.isEmpty == false {
                token.key = fullKey
            }
            return token
        }
        return tokens
    }

    func fetchAccountQuota(accessToken: String, userID: String?) async throws -> AccountQuotaSnapshot {
        var request = try managementRequest(
            url: accountSelfEndpoint(),
            method: "GET",
            accessToken: accessToken,
            userID: userID
        )
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try parseAccountQuota(from: data)
    }

    func fetchTodayTokenUsage(accessToken: String, userID: String?, tokenName: String, date: Date = .now) async throws -> Int64 {
        var request = try managementRequest(
            url: logStatEndpoint(tokenName: tokenName, date: date),
            method: "GET",
            accessToken: accessToken,
            userID: userID
        )
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try parseLogStatQuota(from: data)
    }

    func testModelConnectivity(
        modelID: String,
        mode: TestMode,
        interface: OpenAIModelInterface? = nil
    ) async throws -> OpenAIModelTestOutcome {
        let modelInterface = interface ?? OpenAIModelInterface.recommended(for: modelID)
        let startedAt = ContinuousClock.now

        switch modelInterface {
        case .chatCompletions:
            switch mode {
            case .nonStream:
                try await testNonStream(modelID: modelID)
            case .stream:
                try await testStream(modelID: modelID)
            }
        case .responses:
            switch mode {
            case .nonStream:
                try await testResponses(modelID: modelID, stream: false)
            case .stream:
                try await testResponses(modelID: modelID, stream: true)
            }
        case .embeddings:
            guard mode != .stream else {
                throw NewAPIClientError.api("Embedding 接口不支持流式测试")
            }
            try await testEmbeddings(modelID: modelID)
        }

        let elapsed = startedAt.duration(to: .now)
        let latencyMS = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return OpenAIModelTestOutcome(interface: modelInterface, latencyMS: latencyMS)
    }

    private func testNonStream(modelID: String) async throws {
        var request = try authorizedRequest(url: openAIEndpoint(path: "chat/completions"), method: "POST")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: modelID,
            messages: [ChatMessage(role: "user", content: "Reply with OK only.")],
            stream: false,
            temperature: 0,
            maxTokens: 8
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard decoded.choices.isEmpty == false else {
            throw NewAPIClientError.api("响应中没有 choices")
        }
    }

    private func testStream(modelID: String) async throws {
        var request = try authorizedRequest(url: openAIEndpoint(path: "chat/completions"), method: "POST")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: modelID,
            messages: [ChatMessage(role: "user", content: "Reply with OK only.")],
            stream: true,
            temperature: 0,
            maxTokens: 8
        ))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response: response, data: nil)

        var sawData = false
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else {
                continue
            }

            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }

            if payload.isEmpty == false {
                sawData = true
                break
            }
        }

        guard sawData else {
            throw NewAPIClientError.api("流式响应没有收到 data 事件")
        }
    }

    private func testEmbeddings(modelID: String) async throws {
        var request = try authorizedRequest(url: openAIEndpoint(path: "embeddings"), method: "POST")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(EmbeddingsRequest(
            model: modelID,
            input: ["ModelsBar connectivity test"]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(EmbeddingsResponse.self, from: data)
        guard decoded.data.contains(where: { $0.embedding.isEmpty == false }) else {
            throw NewAPIClientError.api("响应中没有 embedding")
        }
    }

    private func testResponses(modelID: String, stream: Bool) async throws {
        var request = try authorizedRequest(url: openAIEndpoint(path: "responses"), method: "POST")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(ResponsesRequest(
            model: modelID,
            input: "Reply with OK only.",
            stream: stream,
            maxOutputTokens: 8
        ))

        if stream {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            try validate(response: response, data: nil)

            var sawData = false
            for try await line in bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("data:") else {
                    continue
                }

                let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    break
                }

                if payload.isEmpty == false {
                    sawData = true
                    break
                }
            }

            guard sawData else {
                throw NewAPIClientError.api("Responses 流式响应没有收到 data 事件")
            }
            return
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        guard decoded.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NewAPIClientError.api("Responses 响应中没有 id")
        }
    }

    private func authorizedRequest(url: URL, method: String) throws -> URLRequest {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NewAPIClientError.invalidAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func managementRequest(url: URL, method: String, accessToken: String, userID: String?) throws -> URLRequest {
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.isEmpty == false else {
            throw NewAPIClientError.invalidAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let userID, userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue(userID.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "New-Api-User")
        }

        return request
    }

    private func openAIEndpoint(path: String) throws -> URL {
        let base = try parsedBaseURL()
        let trimmedPath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmedPath.split(separator: "/").last == "v1" {
            return base.appending(path: path)
        }

        return base.appending(path: "v1").appending(path: path)
    }

    private func usageEndpoint() throws -> URL {
        var base = try parsedBaseURL()
        let pathParts = base.path.split(separator: "/").map(String.init)

        if pathParts.last == "v1" {
            base.deleteLastPathComponent()
        }

        return base.appending(path: "api").appending(path: "usage").appending(path: "token/")
    }

    private func tokenManagementEndpoint() throws -> URL {
        let base = try managementBaseURL()
        var components = URLComponents(url: base.appending(path: "api").appending(path: "token/"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "page_size", value: "1000"),
            URLQueryItem(name: "size", value: "1000")
        ]

        guard let url = components?.url else {
            throw NewAPIClientError.invalidBaseURL
        }

        return url
    }

    private func tokenKeysBatchEndpoint() throws -> URL {
        try managementBaseURL()
            .appending(path: "api")
            .appending(path: "token")
            .appending(path: "batch")
            .appending(path: "keys")
    }

    private func tokenKeyEndpoint(tokenID: Int) throws -> URL {
        try managementBaseURL()
            .appending(path: "api")
            .appending(path: "token")
            .appending(path: "\(tokenID)")
            .appending(path: "key")
    }

    private func accountSelfEndpoint() throws -> URL {
        try managementBaseURL()
            .appending(path: "api")
            .appending(path: "user")
            .appending(path: "self")
    }

    private func logStatEndpoint(tokenName: String, date: Date) throws -> URL {
        let base = try managementBaseURL()
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        var components = URLComponents(url: base.appending(path: "api").appending(path: "log").appending(path: "self").appending(path: "stat"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "start_timestamp", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_timestamp", value: String(Int(end.timeIntervalSince1970))),
            URLQueryItem(name: "token_name", value: tokenName)
        ]

        guard let url = components?.url else {
            throw NewAPIClientError.invalidBaseURL
        }

        return url
    }

    private func managementBaseURL() throws -> URL {
        var base = try parsedBaseURL()
        let pathParts = base.path.split(separator: "/").map(String.init)

        if pathParts.last == "v1" {
            base.deleteLastPathComponent()
        }

        return base
    }

    private func parsedBaseURL() throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") else {
            throw NewAPIClientError.invalidBaseURL
        }
        return url
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NewAPIClientError.api("无效的 HTTP 响应")
        }

        guard 200..<300 ~= http.statusCode else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NewAPIClientError.httpStatus(http.statusCode, body)
        }
    }

    private func parseManagedTokens(from data: Data) throws -> [ManagedToken] {
        let json = try JSONSerialization.jsonObject(with: data)

        if let dictionary = json as? [String: Any] {
            if let success = dictionary["success"] as? Bool, success == false {
                throw NewAPIClientError.api(dictionary["message"] as? String ?? "同步令牌失败")
            }

            if let code = dictionary["code"] as? Bool, code == false {
                throw NewAPIClientError.api(dictionary["message"] as? String ?? "同步令牌失败")
            }

            if let items = tokenItems(from: dictionary["data"]) ?? tokenItems(from: dictionary["items"]) {
                return items
            }
        }

        if let array = json as? [[String: Any]] {
            return array.compactMap(ManagedToken.init(json:))
        }

        throw NewAPIClientError.api("无法解析令牌列表响应")
    }

    private func tokenItems(from value: Any?) -> [ManagedToken]? {
        if let array = value as? [[String: Any]] {
            return array.compactMap(ManagedToken.init(json:))
        }

        if let dictionary = value as? [String: Any] {
            for key in ["items", "tokens", "data", "rows", "list"] {
                if let array = dictionary[key] as? [[String: Any]] {
                    return array.compactMap(ManagedToken.init(json:))
                }
            }
        }

        return nil
    }

    private func fetchManagedTokenKeys(accessToken: String, userID: String?, tokenIDs: [Int]) async throws -> [Int: String] {
        guard tokenIDs.isEmpty == false else {
            return [:]
        }

        var request = try managementRequest(
            url: tokenKeysBatchEndpoint(),
            method: "POST",
            accessToken: accessToken,
            userID: userID
        )
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(ManagedTokenKeysBatchRequest(ids: tokenIDs))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try parseManagedTokenKeys(from: data)
    }

    private func fetchManagedTokenKey(accessToken: String, userID: String?, tokenID: Int) async throws -> String {
        var request = try managementRequest(
            url: tokenKeyEndpoint(tokenID: tokenID),
            method: "POST",
            accessToken: accessToken,
            userID: userID
        )
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try parseManagedTokenKey(from: data)
    }

    private func fetchAllManagedTokenKeys(accessToken: String, userID: String?, tokens: [ManagedToken]) async throws -> [Int: String] {
        guard tokens.isEmpty == false else {
            return [:]
        }

        var keysByID: [Int: String] = [:]
        let ids = tokens.map(\.id)

        for chunkStart in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids[chunkStart..<min(chunkStart + 100, ids.count)])
            do {
                let chunkKeys = try await fetchManagedTokenKeys(
                    accessToken: accessToken,
                    userID: userID,
                    tokenIDs: chunk
                )
                keysByID.merge(chunkKeys) { current, _ in current }
            } catch {
                for tokenID in chunk {
                    if let fullKey = try? await fetchManagedTokenKey(
                        accessToken: accessToken,
                        userID: userID,
                        tokenID: tokenID
                    ) {
                        keysByID[tokenID] = fullKey
                    }
                }
            }
        }

        return keysByID
    }

    private func parseManagedTokenKeys(from data: Data) throws -> [Int: String] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            return [:]
        }

        if let success = dictionary["success"] as? Bool, success == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "同步令牌密钥失败")
        }

        if let code = dictionary["code"] as? Bool, code == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "同步令牌密钥失败")
        }

        let keyContainer = (dictionary["data"] as? [String: Any])?["keys"] ?? dictionary["keys"]
        let directData = dictionary["data"] as? [String: Any]
        guard let keys = (keyContainer as? [String: Any]) ?? directData else {
            return [:]
        }

        return keys.reduce(into: [Int: String]()) { result, pair in
            guard let id = Int(pair.key),
                  let key = JSONValue.stringValue(pair.value),
                  key.isEmpty == false else {
                return
            }
            result[id] = key
        }
    }

    private func parseManagedTokenKey(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw NewAPIClientError.api("无法解析令牌密钥响应")
        }

        if let success = dictionary["success"] as? Bool, success == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "同步令牌密钥失败")
        }

        if let code = dictionary["code"] as? Bool, code == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "同步令牌密钥失败")
        }

        if let data = dictionary["data"] as? [String: Any],
           let key = JSONValue.stringValue(data["key"]),
           key.isEmpty == false {
            return key
        }

        if let key = JSONValue.stringValue(dictionary["key"]),
           key.isEmpty == false {
            return key
        }

        throw NewAPIClientError.api("响应中没有完整 Key")
    }

    private func parseAccountQuota(from data: Data) throws -> AccountQuotaSnapshot {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw NewAPIClientError.api("无法解析账号额度响应")
        }

        if let success = dictionary["success"] as? Bool, success == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "读取账号额度失败")
        }

        if let code = dictionary["code"] as? Bool, code == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "读取账号额度失败")
        }

        let account = (dictionary["data"] as? [String: Any]) ?? dictionary
        guard let quota = JSONValue.int64Value(account["quota"]),
              let usedQuota = JSONValue.int64Value(account["used_quota"] ?? account["usedQuota"]) else {
            throw NewAPIClientError.api("账号额度响应缺少 quota 或 used_quota")
        }

        return AccountQuotaSnapshot(
            username: JSONValue.stringValue(account["username"]),
            displayName: JSONValue.stringValue(account["display_name"] ?? account["displayName"]),
            email: JSONValue.stringValue(account["email"]),
            group: JSONValue.stringValue(account["group"]),
            quota: quota,
            usedQuota: usedQuota,
            requestCount: JSONValue.intValue(account["request_count"] ?? account["requestCount"])
        )
    }

    private func parseLogStatQuota(from data: Data) throws -> Int64 {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [String: Any] else {
            throw NewAPIClientError.api("无法解析今日消耗响应")
        }

        if let success = dictionary["success"] as? Bool, success == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "读取今日消耗失败")
        }

        if let code = dictionary["code"] as? Bool, code == false {
            throw NewAPIClientError.api(dictionary["message"] as? String ?? "读取今日消耗失败")
        }

        if let data = dictionary["data"] as? [String: Any],
           let quota = JSONValue.int64Value(data["quota"]) {
            return quota
        }

        if let quota = JSONValue.int64Value(dictionary["quota"]) {
            return quota
        }

        throw NewAPIClientError.api("今日消耗响应缺少 quota")
    }
}

private extension ManagedToken {
    init?(json: [String: Any]) {
        guard let id = JSONValue.intValue(json["id"]),
              let key = JSONValue.stringValue(json["key"] ?? json["token"] ?? json["value"]),
              key.isEmpty == false else {
            return nil
        }

        self.id = id
        name = JSONValue.stringValue(json["name"] ?? json["token_name"]) ?? "Token \(id)"
        self.key = key
        createdTime = JSONValue.int64Value(json["created_time"] ?? json["created_at"])
        status = JSONValue.intValue(json["status"])
        remainQuota = JSONValue.int64Value(json["remain_quota"] ?? json["remaining_quota"] ?? json["quota"])
        usedQuota = JSONValue.int64Value(json["used_quota"])
        todayUsedQuota = JSONValue.int64Value(json["today_quota"] ?? json["today_used_quota"] ?? json["used_quota_today"] ?? json["daily_quota"] ?? json["daily_used_quota"])
        unlimitedQuota = JSONValue.boolValue(json["unlimited_quota"])
        expiredTime = JSONValue.int64Value(json["expired_time"] ?? json["expires_at"])
    }
}

private enum JSONValue {
    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    static func int64Value(_ value: Any?) -> Int64? {
        if let int64 = value as? Int64 {
            return int64
        }

        if let int = value as? Int {
            return Int64(int)
        }

        if let number = value as? NSNumber {
            return number.int64Value
        }

        if let string = value as? String {
            return Int64(string)
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
}

private struct ManagedTokenKeysBatchRequest: Encodable {
    var ids: [Int]
}

private extension String {
    var isMaskedTokenValue: Bool {
        contains("*") || contains("•")
    }
}

struct TokenUsageFetchResult: Equatable {
    var usage: TokenUsage
    var rawJSON: String
}

struct OpenAIModelTestOutcome: Equatable {
    var interface: OpenAIModelInterface
    var latencyMS: Int

    var message: String {
        switch interface {
        case .chatCompletions:
            "Chat Completions OK"
        case .responses:
            "Responses OK"
        case .embeddings:
            "Embeddings OK"
        }
    }
}

enum OpenAIModelInterface: String, Codable, CaseIterable, Equatable, Hashable {
    case chatCompletions
    case responses
    case embeddings

    var title: String {
        switch self {
        case .chatCompletions:
            return "/v1/chat/completions"
        case .responses:
            return "/v1/responses"
        case .embeddings:
            return "/v1/embeddings"
        }
    }

    var shortTitle: String {
        switch self {
        case .chatCompletions:
            return "Chat"
        case .responses:
            return "Responses"
        case .embeddings:
            return "Embeddings"
        }
    }

    var supportsStreamTesting: Bool {
        switch self {
        case .chatCompletions:
            true
        case .responses:
            true
        case .embeddings:
            false
        }
    }

    static func availableInterfaces(for modelID: String) -> [OpenAIModelInterface] {
        let lowercased = modelID.lowercased()
        if lowercased.contains("embedding") {
            return [.embeddings]
        }
        return [.chatCompletions, .responses]
    }

    static func recommended(for modelID: String) -> OpenAIModelInterface {
        let lowercased = modelID.lowercased()
        if lowercased.contains("embedding") {
            return .embeddings
        }
        if lowercased.contains("codex") {
            return .responses
        }
        return .chatCompletions
    }

    init(modelID: String) {
        self = Self.recommended(for: modelID)
    }
}

enum NewAPIClientError: LocalizedError {
    case invalidBaseURL
    case invalidAPIKey
    case httpStatus(Int, String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "BaseURL 无效"
        case .invalidAPIKey:
            "ApiKey 为空"
        case .httpStatus(let status, let body):
            "HTTP \(status): \(body)"
        case .api(let message):
            message
        }
    }
}

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    var id: String
}

private struct NewAPIUsageResponse: Decodable {
    var code: Bool
    var message: String
    var data: NewAPITokenUsage
}

private struct NewAPITokenUsage: Decodable {
    var object: String
    var name: String
    var totalGranted: Int64
    var totalUsed: Int64
    var totalAvailable: Int64
    var unlimitedQuota: Bool
    var modelLimits: [String: Bool]
    var modelLimitsEnabled: Bool
    var expiresAt: Int64

    var tokenUsage: TokenUsage {
        TokenUsage(
            object: object,
            name: name,
            totalGranted: totalGranted,
            totalUsed: totalUsed,
            totalAvailable: totalAvailable,
            unlimitedQuota: unlimitedQuota,
            modelLimits: modelLimits,
            modelLimitsEnabled: modelLimitsEnabled,
            expiresAt: expiresAt
        )
    }
}

private struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool
    var temperature: Double
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Decodable {
    var choices: [ChatCompletionChoice]
}

private struct ChatCompletionChoice: Decodable {
    var index: Int?
}

private struct EmbeddingsRequest: Encodable {
    var model: String
    var input: [String]
}

private struct EmbeddingsResponse: Decodable {
    var data: [EmbeddingData]
}

private struct EmbeddingData: Decodable {
    var embedding: [Double]
}

private struct ResponsesRequest: Encodable {
    var model: String
    var input: String
    var stream: Bool
    var maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case stream
        case maxOutputTokens = "max_output_tokens"
    }
}

private struct ResponsesResponse: Decodable {
    var id: String
}
