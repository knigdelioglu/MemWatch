import Foundation

enum CleanupIgnoreKind: String, Codable, CaseIterable, Sendable {
    case path
    case project
    case application
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
    let ignoredProjectPaths: Set<String>
    let ignoredApplicationIdentifiers: Set<String>

    init(
        ignoredRuleIDs: Set<CleanupRuleID> = [],
        ignoredCategories: Set<CleanupCategory> = [],
        ignoredScannerIDs: Set<CleanupScannerID> = [],
        ignoredProjectPaths: Set<String> = [],
        ignoredApplicationIdentifiers: Set<String> = []
    ) {
        self.ignoredRuleIDs = ignoredRuleIDs
        self.ignoredCategories = ignoredCategories
        self.ignoredScannerIDs = ignoredScannerIDs
        self.ignoredProjectPaths = Set(ignoredProjectPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        self.ignoredApplicationIdentifiers = ignoredApplicationIdentifiers
    }

    func skips(scanner: any CleanupScanner) -> Bool {
        ignoredScannerIDs.contains(scanner.id) || ignoredCategories.contains(scanner.category)
    }

    func skips(candidate: CleanupCandidate) -> Bool {
        if ignoredRuleIDs.contains(candidate.ruleID) ||
            ignoredCategories.contains(candidate.category) ||
            ignoredScannerIDs.contains(candidate.scannerID) {
            return true
        }

        if ignoredProjectPaths.contains(where: {
            CleanupPathValidator.path(candidate.url.path, isEqualToOrDescendantOf: $0)
        }) {
            return true
        }

        if let identifier = Self.applicationIdentifier(for: candidate) {
            return ignoredApplicationIdentifiers.contains { ignored in
                identifier == ignored ||
                    identifier.hasPrefix(ignored + ".") ||
                    ignored.hasPrefix(identifier + ".")
            }
        }
        return false
    }

    static func applicationIdentifier(for candidate: CleanupCandidate) -> String? {
        for prefix in ["System orphan: ", "Orphan: "] where candidate.displayName.hasPrefix(prefix) {
            let value = String(candidate.displayName.dropFirst(prefix.count))
            if looksLikeBundleIdentifier(value) { return normalizedIdentifier(value) }
        }

        let components = candidate.url.standardizedFileURL.pathComponents
        let markers: [[String]] = [
            ["Library", "Caches"],
            ["Library", "Containers"],
            ["Library", "Group Containers"],
            ["Library", "Preferences"],
            ["Library", "HTTPStorages"],
            ["Library", "WebKit"],
            ["Library", "Saved Application State"]
        ]
        for marker in markers {
            guard let index = sequenceIndex(marker, in: components) else { continue }
            let valueIndex = index + marker.count
            guard valueIndex < components.count else { continue }
            var value = components[valueIndex]
            for suffix in [".savedState", ".plist"] where value.hasSuffix(suffix) {
                value.removeLast(suffix.count)
            }
            value = normalizedIdentifier(value)
            if looksLikeBundleIdentifier(value) { return value }
        }
        return nil
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.hasPrefix("group.") ? String(value.dropFirst("group.".count)) : value
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        return components.count >= 2 && components.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    private static func sequenceIndex(_ needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return start }
        }
        return nil
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
        var projects = Set<String>()
        var applications = Set<String>()
        var ruleIDs = Set<CleanupRuleID>()
        var categories = Set<CleanupCategory>()
        var scanners = Set<CleanupScannerID>()

        for rule in rules {
            switch rule.kind {
            case .path:
                paths.insert(URL(fileURLWithPath: rule.value).standardizedFileURL.path)
            case .project:
                let path = URL(fileURLWithPath: rule.value).standardizedFileURL.path
                paths.insert(path)
                projects.insert(path)
            case .application:
                applications.insert(rule.value)
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
                ignoredScannerIDs: scanners,
                ignoredProjectPaths: projects,
                ignoredApplicationIdentifiers: applications
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

struct CleanupHistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let mode: CleanupExecutionMode
    let requestedCount: Int
    let successfulCount: Int
    let failedCount: Int
    let reclaimedBytes: UInt64
    let movedToTrashBytes: UInt64
    let observedFreeSpaceDeltaBytes: UInt64?
    let results: [CleanupExecutionItemResult]

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case mode
        case requestedCount
        case successfulCount
        case failedCount
        case reclaimedBytes
        case movedToTrashBytes
        case observedFreeSpaceDeltaBytes
        case results
    }

    private struct LegacyExecutionItemResult: Decodable {
        let id: UUID
        let candidateID: UUID
        let ruleID: String
        let path: String
        let displayName: String
        let status: CleanupExecutionStatus
        let reclaimedBytes: UInt64
        let message: String
    }

    init(report: CleanupExecutionReport) {
        id = report.id
        timestamp = report.finishedAt
        mode = report.mode
        requestedCount = report.results.count
        successfulCount = report.successfulCount
        failedCount = report.failureCount
        reclaimedBytes = report.reclaimedBytes
        movedToTrashBytes = report.movedToTrashBytes
        observedFreeSpaceDeltaBytes = report.observedFreeSpaceDeltaBytes
        results = report.results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mode = try container.decode(CleanupExecutionMode.self, forKey: .mode)
        requestedCount = try container.decode(Int.self, forKey: .requestedCount)
        successfulCount = try container.decode(Int.self, forKey: .successfulCount)
        failedCount = try container.decode(Int.self, forKey: .failedCount)

        let storedReclaimedBytes = try container.decode(UInt64.self, forKey: .reclaimedBytes)
        let decodedCurrentResults = try? container.decode([CleanupExecutionItemResult].self, forKey: .results)
        if let decodedCurrentResults {
            results = decodedCurrentResults
            reclaimedBytes = storedReclaimedBytes
        } else {
            let legacyResults = try container.decode([LegacyExecutionItemResult].self, forKey: .results)
            results = legacyResults.map { legacy in
                let movedToTrash = legacy.status == .movedToTrash
                return CleanupExecutionItemResult(
                    id: legacy.id,
                    candidateID: legacy.candidateID,
                    ruleID: legacy.ruleID,
                    path: legacy.path,
                    displayName: legacy.displayName,
                    status: legacy.status,
                    affectedBytes: legacy.reclaimedBytes,
                    reclaimedBytes: movedToTrash ? 0 : legacy.reclaimedBytes,
                    message: legacy.message
                )
            }
            reclaimedBytes = results.reduce(0) { partial, result in
                let (value, overflow) = partial.addingReportingOverflow(result.reclaimedBytes)
                return overflow ? UInt64.max : value
            }
        }

        movedToTrashBytes = try container.decodeIfPresent(UInt64.self, forKey: .movedToTrashBytes) ?? results
            .filter { $0.status == .movedToTrash }
            .reduce(0) { partial, result in
                let (value, overflow) = partial.addingReportingOverflow(result.affectedBytes)
                return overflow ? UInt64.max : value
            }
        observedFreeSpaceDeltaBytes = try container.decodeIfPresent(UInt64.self, forKey: .observedFreeSpaceDeltaBytes)
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
    var cleanupEnabled: Bool
    var privilegedOperationsEnabled: Bool
    var privateBackendEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case requestedRootPaths
        case projectRootPaths
        case cleanupEnabled
        case privilegedOperationsEnabled
        case privateBackendEnabled
    }

    static func defaults(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanupPreferences {
        CleanupPreferences(
            requestedRootPaths: ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].map {
                home.appendingPathComponent($0, isDirectory: true).path
            },
            projectRootPaths: ["Projects", "Code", "dev", "GitHub", "Workspace"].map {
                home.appendingPathComponent($0, isDirectory: true).path
            },
            cleanupEnabled: true,
            privilegedOperationsEnabled: true,
            privateBackendEnabled: true
        )
    }

    init(
        requestedRootPaths: [String],
        projectRootPaths: [String],
        cleanupEnabled: Bool,
        privilegedOperationsEnabled: Bool,
        privateBackendEnabled: Bool
    ) {
        self.requestedRootPaths = requestedRootPaths
        self.projectRootPaths = projectRootPaths
        self.cleanupEnabled = cleanupEnabled
        self.privilegedOperationsEnabled = privilegedOperationsEnabled
        self.privateBackendEnabled = privateBackendEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CleanupPreferences.defaults()
        requestedRootPaths = try container.decodeIfPresent([String].self, forKey: .requestedRootPaths) ?? defaults.requestedRootPaths
        projectRootPaths = try container.decodeIfPresent([String].self, forKey: .projectRootPaths) ?? defaults.projectRootPaths
        cleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? true
        privilegedOperationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .privilegedOperationsEnabled) ?? true
        privateBackendEnabled = try container.decodeIfPresent(Bool.self, forKey: .privateBackendEnabled) ?? true
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
