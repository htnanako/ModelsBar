import Foundation

struct CCSwitchCodexAccountService {
    static let defaultDatabasePath = "\(NSHomeDirectory())/.cc-switch/cc-switch.db"

    var databasePath: String

    init(databasePath: String = Self.defaultDatabasePath) {
        let trimmedPath = databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.databasePath = trimmedPath.isEmpty ? Self.defaultDatabasePath : trimmedPath
    }

    func loadCodexAuthFiles() throws -> [CodexAuthFilePayload] {
        let rows = try fetchCodexProviderRows()

        return rows.compactMap { row in
            guard let settings = row.settings else {
                return nil
            }

            let category = row.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let websiteURL = row.websiteURL?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let authMode = settings.auth?.authMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isOfficialCodexAccount = category == "official" ||
                websiteURL?.contains("chatgpt.com/codex") == true ||
                authMode == "chatgpt"

            guard isOfficialCodexAccount,
                  let tokens = settings.auth?.tokens,
                  let accessToken = nonEmpty(tokens.accessToken),
                  let idToken = nonEmpty(tokens.idToken),
                  let accountID = nonEmpty(tokens.accountID) else {
                return nil
            }

            var payloadObject: [String: Any] = [
                "access_token": accessToken,
                "id_token": idToken,
                "account_id": accountID,
                "type": "codex"
            ]

            if let refreshToken = nonEmpty(tokens.refreshToken) {
                payloadObject["refresh_token"] = refreshToken
            }
            if let lastRefresh = nonEmpty(settings.auth?.lastRefresh) {
                payloadObject["last_refresh"] = lastRefresh
            }

            guard let data = try? JSONSerialization.data(withJSONObject: payloadObject) else {
                return nil
            }

            return CodexAuthFilePayload(
                name: "cc-switch:\(row.id)",
                provider: "codex",
                status: "active",
                statusMessage: row.name,
                disabled: false,
                unavailable: false,
                lastRefresh: parseDate(settings.auth?.lastRefresh),
                data: data
            )
        }
    }

    private func fetchCodexProviderRows() throws -> [CCSwitchProviderRow] {
        let resolvedPath = (databasePath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw CCSwitchCodexAccountServiceError.databaseNotFound(resolvedPath)
        }

        let query = """
        SELECT id, name, category, website_url, settings_config, sort_index
        FROM providers
        WHERE app_type = 'codex'
        ORDER BY sort_index, name;
        """

        let data = try runSQLiteJSON(databasePath: resolvedPath, query: query)
        if data.isEmpty {
            return []
        }
        return try JSONDecoder().decode([CCSwitchProviderRow].self, from: data)
    }

    private func runSQLiteJSON(databasePath: String, query: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databasePath, query]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CCSwitchCodexAccountServiceError.sqliteUnavailable(error.localizedDescription)
        }

        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CCSwitchCodexAccountServiceError.sqliteQueryFailed(message ?? "读取 CC Switch 数据库失败")
        }

        return output
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = nonEmpty(value) else {
            return nil
        }

        if let seconds = Double(value) {
            return Date(timeIntervalSince1970: seconds)
        }

        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return formatter.date(from: value)
    }
}

private struct CCSwitchProviderRow: Decodable {
    var id: String
    var name: String
    var category: String?
    var websiteURL: String?
    var settingsConfig: String?

    var settings: CCSwitchProviderSettings? {
        guard let data = settingsConfig?.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CCSwitchProviderSettings.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case websiteURL = "website_url"
        case settingsConfig = "settings_config"
    }
}

private struct CCSwitchProviderSettings: Decodable {
    var auth: Auth?

    struct Auth: Decodable {
        var authMode: String?
        var tokens: Tokens?
        var lastRefresh: String?

        private enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case tokens
            case lastRefresh = "last_refresh"
        }
    }

    struct Tokens: Decodable {
        var accessToken: String?
        var idToken: String?
        var refreshToken: String?
        var accountID: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case idToken = "id_token"
            case refreshToken = "refresh_token"
            case accountID = "account_id"
        }
    }
}

private enum CCSwitchCodexAccountServiceError: LocalizedError {
    case databaseNotFound(String)
    case sqliteUnavailable(String)
    case sqliteQueryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "未找到 CC Switch 数据库：\(path)"
        case .sqliteUnavailable(let message):
            return "无法启动 sqlite3：\(message)"
        case .sqliteQueryFailed(let message):
            return "读取 CC Switch 数据库失败：\(message)"
        }
    }
}
