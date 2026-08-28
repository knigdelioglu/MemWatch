import Foundation

enum CleanupIgnoreKind: String, Codable, CaseIterable, Sendable {
    case path
    case rule
    case category
    case scanner
}

struct CleanupIgnoreRule: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: CleanupIgnoreKind
    let value: String
    let recursive: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: CleanupIgnoreKind,
        value: String,
        recursive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.recursive = recursive
        self.createdAt = createdAt
    }
}

struct CleanupScanPolicy: Sendable {
    let ignoredRuleIDs: Set<CleanupRuleID>
    let ignoredCategories: Set<CleanupCategory>
    let ignoredScannerIDs: Set<CleanupScannerID>

    init(
        ignoredRuleIDs: Set<CleanupRuleID> = [],
        ignoredCategories: Set<CleanupCategory> = [],
        ignoredScannerIDs: Set<CleanupScannerID> = []
    ) {
        self.ignoredRuleIDs = ignoredRuleIDs
        self.ignoredCategories = ignoredCategories
        self.ignoredScannerIDs = ignoredScannerIDs
    }

    func skips(scanner: any CleanupScanner) -> Bool {
        ignoredScannerIDs.contains(scanner.id) || ignoredCategories.contains(scanner.category)
    }

    func skips(candidate: CleanupCandidate) -> Bool {
        ignoredRuleIDs.contains(candidate.ruleID) ||
            ignoredCategories.contains(candidate.category) ||
            ignoredScannerIDs.contains(candidate.scannerID)
    }
}

struct CleanupIgnoreSnapshot: Sendable {
    let pathValues: Set<String>
    let policy: CleanupScanPolicy
}

actor CleanupIgnoreStore {
    private let fileURL: URL

    init(fileURL: URL = CleanupPersistencePaths.ignoreFile) {
        self.fileURL = fileURL
    }

    func load() -> [CleanupIgnoreRule] {
        Self.read([CleanupIgnoreRule].self, from: fileURL) ?? []
    }

    func snapshot() -> CleanupIgnoreSnapshot {
        let rules = load()
        var paths = Set<String>()
        var ruleIDs = Set<CleanupRuleID>()
        var categories = Set<CleanupCategory>()
        var scanners = Set<CleanupScannerID>()

        for rule in rules {
            switch rule.kind {
            case .path:
                paths.insert(URL(fileURLWithPath: rule.value).standardizedFileURL.path)
            case .rule:
                ruleIDs.insert(CleanupRuleID(rawValue: rule.value))
            case .category:
                if let category = CleanupCategory(rawValue: rule.value) { categories.insert(category) }
            case .scanner:
                scanners.insert(CleanupScannerID(rawValue: rule.value))
            }
        }
        return CleanupIgnoreSnapshot(
            pathValues: paths,
            policy: CleanupScanPolicy(
                ignoredRuleIDs: ruleIDs,
                ignoredCategories: categories,
                ignoredScannerIDs: scanners
            )
        )
    }

    @discardableResult
    func add(_ rule: CleanupIgnoreRule) throws -> [CleanupIgnoreRule] {
        var rules = load()
        if !rules.contains(where: { $0.kind == rule.kind && $0.value == rule.value }) {
            rules.append(rule)
        }
        try save(rules)
        return rules
    }

    @discardableResult
    func remove(id: UUID) throws -> [CleanupIgnoreRule] {
        var rules = load()
        rules.removeAll { $0.id == id }
        try save(rules)
        return rules
    }

    func save(_ rules: [CleanupIgnoreRule]) throws {
        try Self.write(rules, to: fileURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.memWatchCleanup.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try CleanupPersistencePaths.ensureDirectory()
        let data = try JSONEncoder.memWatchCleanup.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

struct CleanupHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let mode: CleanupExecutionMode
    let requestedCount: Int
    let successfulCount: Int
    let failedCount: Int
    let reclaimedBytes: UInt64
    let results: [CleanupExecutionItemResult]

    init(report: CleanupExecutionReport) {
        id = report.id
        timestamp = report.finishedAt
        mode = report.mode
        requestedCount = report.results.count
        successfulCount = report.successfulCount
        failedCount = report.failureCount
        reclaimedBytes = report.reclaimedBytes
        results = report.results
    }
}

actor CleanupHistoryStore {
    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = CleanupPersistencePaths.historyFile, limit: Int = 100) {
        self.fileURL = fileURL
        self.limit = max(1, limit)
    }

    func load() -> [CleanupHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder.memWatchCleanup.decode([CleanupHistoryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    @discardableResult
    func append(report: CleanupExecutionReport) throws -> [CleanupHistoryEntry] {
        var entries = load()
        entries.insert(CleanupHistoryEntry(report: report), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        try CleanupPersistencePaths.ensureDirectory()
        let data = try JSONEncoder.memWatchCleanup.encode(entries)
        try data.write(to: fileURL, options: [.atomic])
        return entries
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

struct CleanupPreferences: Codable, Equatable, Sendable {
    var requestedRootPaths: [String]
    var projectRootPaths: [String]
    var privateBackendEnabled: Bool

    static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanupPreferences {
        CleanupPreferences(
            requestedRootPaths: ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].map {
                home.appendingPathComponent($0, isDirectory: true).path
            },
            projectRootPaths: ["Projects", "Code", "dev", "GitHub", "Workspace"].map {
                home.appendingPathComponent($0, isDirectory: true).path
            },
            privateBackendEnabled: true
        )
    }
}

actor CleanupPreferencesStore {
    private let fileURL: URL

    init(fileURL: URL = CleanupPersistencePaths.preferencesFile) {
        self.fileURL = fileURL
    }

    func load() -> CleanupPreferences {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder.memWatchCleanup.decode(CleanupPreferences.self, from: data) else {
            return .defaults()
        }
        return value
    }

    func save(_ preferences: CleanupPreferences) throws {
        try CleanupPersistencePaths.ensureDirectory()
        let data = try JSONEncoder.memWatchCleanup.encode(preferences)
        try data.write(to: fileURL, options: [.atomic])
    }
}

enum CleanupPersistencePaths {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MemWatch/Cleanup", isDirectory: true)
    }

    static var ignoreFile: URL { directory.appendingPathComponent("ignore-rules.json") }
    static var historyFile: URL { directory.appendingPathComponent("history.json") }
    static var preferencesFile: URL { directory.appendingPathComponent("preferences.json") }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

private extension JSONEncoder {
    static var memWatchCleanup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var memWatchCleanup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
