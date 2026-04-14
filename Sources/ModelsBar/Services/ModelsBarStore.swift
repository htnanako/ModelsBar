import Foundation

struct ModelsBarStore {
    let fileManager: FileManager
    let directoryURL: URL
    let providersURL: URL
    let cacheURL: URL
    let historyURL: URL
    let legacyConfigURL: URL
    let legacyBackupURL: URL

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let directory: URL
        if let directoryURL {
            directory = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? fileManager.homeDirectoryForCurrentUser
            directory = appSupport.appending(path: "ModelsBar", directoryHint: .isDirectory)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        self.directoryURL = directory
        self.providersURL = directory.appending(path: "providers.json")
        self.cacheURL = directory.appending(path: "cache.json")
        self.historyURL = directory.appending(path: "history.json")
        self.legacyConfigURL = directory.appending(path: "config.json")
        self.legacyBackupURL = directory.appending(path: "config.legacy.json")
    }

    func load() -> AppData {
        if hasCompleteSplitStorage {
            archiveLegacyConfigIfNeeded()
            return loadSplitAppData()
        }

        if fileManager.fileExists(atPath: legacyConfigURL.path) {
            do {
                let data = try Data(contentsOf: legacyConfigURL)
                let decoder = makeDecoder()
                let appData = try decoder.decode(AppData.self, from: data)
                try migrateLegacyConfigIfNeeded(appData)
                return appData
            } catch {
                if hasAnySplitStorage {
                    return loadSplitAppData()
                }

                return AppData()
            }
        }

        if hasAnySplitStorage {
            return loadSplitAppData()
        }

        return AppData()
    }

    func save(_ appData: AppData) throws {
        try writeSplitFiles(appData)
    }

    private var hasAnySplitStorage: Bool {
        [providersURL, cacheURL, historyURL].contains { fileManager.fileExists(atPath: $0.path) }
    }

    private var hasCompleteSplitStorage: Bool {
        [providersURL, cacheURL, historyURL].allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    private func loadSplitAppData() -> AppData {
        let providersPayload = loadPayload(ProvidersStoragePayload.self, from: providersURL)
        let cachePayload = loadPayload(CacheStoragePayload.self, from: cacheURL)
        let historyPayload = loadPayload(HistoryStoragePayload.self, from: historyURL)

        return AppData(
            providers: providersPayload?.providers ?? [],
            modelRecords: cachePayload?.modelRecords ?? [],
            quotaRecords: historyPayload?.quotaRecords ?? [],
            testResults: historyPayload?.testResults ?? [],
            updatedAt: [
                providersPayload?.updatedAt,
                cachePayload?.updatedAt,
                historyPayload?.updatedAt
            ]
            .compactMap { $0 }
            .max() ?? .now
        )
    }

    private func migrateLegacyConfigIfNeeded(_ appData: AppData) throws {
        try writeSplitFiles(appData)
        archiveLegacyConfigIfNeeded()
    }

    private func writeSplitFiles(_ appData: AppData) throws {
        try savePayload(
            ProvidersStoragePayload(
                providers: appData.providers,
                updatedAt: appData.updatedAt
            ),
            to: providersURL
        )
        try savePayload(
            CacheStoragePayload(
                modelRecords: appData.modelRecords,
                updatedAt: appData.updatedAt
            ),
            to: cacheURL
        )
        try savePayload(
            HistoryStoragePayload(
                quotaRecords: appData.quotaRecords,
                testResults: appData.testResults,
                updatedAt: appData.updatedAt
            ),
            to: historyURL
        )
    }

    private func loadPayload<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func archiveLegacyConfigIfNeeded() {
        guard fileManager.fileExists(atPath: legacyConfigURL.path) else {
            return
        }

        if fileManager.fileExists(atPath: legacyBackupURL.path) {
            try? fileManager.removeItem(at: legacyConfigURL)
            return
        }

        try? fileManager.moveItem(at: legacyConfigURL, to: legacyBackupURL)
    }

    private func savePayload<T: Encodable>(_ payload: T, to url: URL) throws {
        let data = try makeEncoder().encode(payload)
        try data.write(to: url, options: [.atomic])
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private struct ProvidersStoragePayload: Codable, Equatable {
    var providers: [ProviderConfig] = []
    var updatedAt: Date = .now
}

private struct CacheStoragePayload: Codable, Equatable {
    var modelRecords: [ModelRecord] = []
    var updatedAt: Date = .now
}

private struct HistoryStoragePayload: Codable, Equatable {
    var quotaRecords: [QuotaDailyRecord] = []
    var testResults: [ModelTestResult] = []
    var updatedAt: Date = .now
}
