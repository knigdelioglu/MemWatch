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
            let normalizedIdentifier = identifier.lowercased()
            return ignoredApplicationIdentifiers.contains { ignored in
                let normalizedIgnored = ignored.lowercased()
                return normalizedIdentifier == normalizedIgnored ||
                    normalizedIdentifier.hasPrefix(normalizedIgnored + ".") ||
                    normalizedIgnored.hasPrefix(normalizedIdentifier + ".")
            }
        }
        return false
    }

    static func applicationIdentifier(for candidate: CleanupCandidate) -> String? {
        for prefix in ["System orphan: ", "Orphan: "] where candidate.displayName.hasPrefix(prefix) {
            let value = String(candidate.displayName.dropFirst(prefix.count))
            if looksLikeBundleIdentifier(value) { return normalizedIdentifier(value).lowercased() }
        }

        let components = candidate.url.standardizedFileURL.pathComponents
        let path = candidate.url.standardizedFileURL.path
        if path.contains("/Library/Application Support/Code/") {
            return "com.microsoft.vscode"
        }
        if path.contains("/Library/Caches/JetBrains") {
            return "com.jetbrains"
        }
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
            if looksLikeBundleIdentifier(value) { return value.lowercased() }
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
    let exactPathValues: Set<String>
    let policy: CleanupScanPolicy
}

enum CleanupPersistenceError: LocalizedError, Equatable {
    case unreadable(URL)
    case malformed(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "Cleanup state could not be read safely: \(url.path)"
        case .malformed(let url):
            return "Cleanup state is malformed and was not applied: \(url.path)"
        }
    }
}

protocol CleanupPreferencesPersisting: Actor {
    func load() async throws -> CleanupPreferences
    func save(_ preferences: CleanupPreferences) async throws
}

/// Revision state shared by initial-load and user-intent tests. A load may
/// publish only when no user intent has appeared since it began.
struct CleanupPreferenceRevisionState: Sendable {
    private(set) var current: UInt64 = 0

    @discardableResult
    mutating func recordUserIntent() -> UInt64 {
        current &+= 1
        return current
    }

    func acceptsInitialLoad(startedAt revision: UInt64) -> Bool {
        current == revision
    }
}

enum LatestIntentWriteOutcome: Equatable, Sendable {
    case persisted
    case superseded
}

/// Serializes durable writes while retaining only the newest pending intent.
///
/// A writer may suspend while its I/O is in flight. New submissions are still
/// accepted during that suspension, but the pipeline never starts a second
/// write until the first one has completed. If a newer revision arrived, the
/// older completion is reported as superseded and the newest value is written
/// next. This makes the final on-disk value deterministic even when a storage
/// backend has delayed or reordered completion callbacks.
actor LatestIntentWritePipeline<Value: Sendable> {
    typealias Writer = @Sendable (Value) async throws -> Void

    private struct Request {
        let revision: UInt64
        let value: Value
    }

    private let writer: Writer
    private var latestRequest: Request?
    private var highestSubmittedRevision: UInt64 = 0
    private var isDraining = false
    private var waiters: [UInt64: [CheckedContinuation<LatestIntentWriteOutcome, Error>]] = [:]

    init(writer: @escaping Writer) {
        self.writer = writer
    }

    var latestSubmittedRevision: UInt64 {
        highestSubmittedRevision
    }

    func submit(_ value: Value, revision: UInt64) async throws -> LatestIntentWriteOutcome {
        guard revision > highestSubmittedRevision else {
            return .superseded
        }

        highestSubmittedRevision = revision
        if let previous = latestRequest {
            // Intermediate requests have not started I/O yet. Complete their
            // waiters immediately; otherwise a 100-event burst would leave
            // continuations suspended forever while only the newest value is
            // retained.
            finish(previous.revision, with: .success(.superseded))
        }
        latestRequest = Request(revision: revision, value: value)

        return try await withCheckedThrowingContinuation { continuation in
            waiters[revision, default: []].append(continuation)
            startDrainingIfNeeded()
        }
    }

    private func startDrainingIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while let request = latestRequest {
            latestRequest = nil

            do {
                try await writer(request.value)
            } catch {
                if let newer = latestRequest, newer.revision > request.revision {
                    finish(request.revision, with: .success(.superseded))
                    continue
                }

                finish(request.revision, with: .failure(error))
                isDraining = false
                return
            }

            if let newer = latestRequest, newer.revision > request.revision {
                finish(request.revision, with: .success(.superseded))
                continue
            }

            finish(request.revision, with: .success(.persisted))
            isDraining = false
            return
        }

        isDraining = false
    }

    private func finish(
        _ revision: UInt64,
        with result: Result<LatestIntentWriteOutcome, Error>
    ) {
        guard let continuations = waiters.removeValue(forKey: revision) else { return }
        continuations.forEach { $0.resume(with: result) }
    }
}

actor CleanupIgnoreStore {
    private let fileURL: URL

    init(fileURL: URL = CleanupPersistencePaths.ignoreFile) {
        self.fileURL = fileURL
    }

    func load() throws -> [CleanupIgnoreRule] {
        try Self.read([CleanupIgnoreRule].self, from: fileURL)
    }

    func snapshot() throws -> CleanupIgnoreSnapshot {
        let rules = try load()
        var paths = Set<String>()
        var exactPaths = Set<String>()
        var projects = Set<String>()
        var applications = Set<String>()
        var ruleIDs = Set<CleanupRuleID>()
        var categories = Set<CleanupCategory>()
        var scanners = Set<CleanupScannerID>()

        for rule in rules {
            guard !rule.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CleanupPersistenceError.malformed(fileURL)
            }
            switch rule.kind {
            case .path:
                guard rule.value.hasPrefix("/") else { throw CleanupPersistenceError.malformed(fileURL) }
                let path = URL(fileURLWithPath: rule.value).standardizedFileURL.path
                guard path.hasPrefix("/") else { throw CleanupPersistenceError.malformed(fileURL) }
                if rule.recursive { paths.insert(path) }
                else { exactPaths.insert(path) }
            case .project:
                guard rule.value.hasPrefix("/") else { throw CleanupPersistenceError.malformed(fileURL) }
                let path = URL(fileURLWithPath: rule.value).standardizedFileURL.path
                guard path.hasPrefix("/") else { throw CleanupPersistenceError.malformed(fileURL) }
                projects.insert(path)
            case .application:
                let identifier = rule.value.lowercased()
                guard Self.looksLikeBundleIdentifier(identifier) else {
                    throw CleanupPersistenceError.malformed(fileURL)
                }
                applications.insert(identifier)
            case .rule:
                ruleIDs.insert(CleanupRuleID(rawValue: rule.value))
            case .category:
                guard let category = CleanupCategory(rawValue: rule.value) else {
                    throw CleanupPersistenceError.malformed(fileURL)
                }
                categories.insert(category)
            case .scanner:
                scanners.insert(CleanupScannerID(rawValue: rule.value))
            }
        }
        return CleanupIgnoreSnapshot(
            pathValues: paths,
            exactPathValues: exactPaths,
            policy: CleanupScanPolicy(
                ignoredRuleIDs: ruleIDs,
                ignoredCategories: categories,
                ignoredScannerIDs: scanners,
                ignoredProjectPaths: projects,
                ignoredApplicationIdentifiers: applications
            )
        )
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        return components.count >= 2 && components.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    @discardableResult
    func add(_ rule: CleanupIgnoreRule) throws -> [CleanupIgnoreRule] {
        var rules = try load()
        if !rules.contains(where: { $0.kind == rule.kind && $0.value == rule.value }) {
            rules.append(rule)
        }
        try save(rules)
        return rules
    }

    @discardableResult
    func remove(id: UUID) throws -> [CleanupIgnoreRule] {
        var rules = try load()
        rules.removeAll { $0.id == id }
        try save(rules)
        return rules
    }

    func save(_ rules: [CleanupIgnoreRule]) throws {
        try Self.write(rules, to: fileURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return try JSONDecoder.memWatchCleanup.decode(type, from: Data("[]".utf8))
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CleanupPersistenceError.unreadable(url)
        }
        do {
            return try JSONDecoder.memWatchCleanup.decode(type, from: data)
        } catch {
            throw CleanupPersistenceError.malformed(url)
        }
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
    let outcome: CleanupExecutionOutcome
    let requestedCount: Int
    let successfulCount: Int
    let failedCount: Int
    let reclaimedBytes: UInt64
    let movedToTrashBytes: UInt64
    let observedFreeSpaceDeltaBytes: UInt64?
    let reclaimVerification: CleanupReclaimVerification
    let results: [CleanupExecutionItemResult]

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case mode
        case outcome
        case requestedCount
        case successfulCount
        case failedCount
        case reclaimedBytes
        case movedToTrashBytes
        case observedFreeSpaceDeltaBytes
        case reclaimVerification
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
        outcome = report.outcome
        requestedCount = report.requestedCount
        successfulCount = report.successfulCount
        failedCount = report.failureCount
        reclaimedBytes = report.reclaimedBytes
        movedToTrashBytes = report.movedToTrashBytes
        observedFreeSpaceDeltaBytes = report.observedFreeSpaceDeltaBytes
        reclaimVerification = report.reclaimVerification
        results = report.results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mode = try container.decode(CleanupExecutionMode.self, forKey: .mode)
        outcome = try container.decodeIfPresent(CleanupExecutionOutcome.self, forKey: .outcome) ?? .completed
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
        reclaimVerification = try container.decodeIfPresent(CleanupReclaimVerification.self, forKey: .reclaimVerification)
            ?? (mode == .apply ? .unavailable : .notMeasured)
    }
}

actor CleanupHistoryStore {
    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = CleanupPersistencePaths.historyFile, limit: Int = 100) {
        self.fileURL = fileURL
        self.limit = max(1, limit)
    }

    func load() throws -> [CleanupHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CleanupPersistenceError.unreadable(fileURL)
        }
        do {
            let entries = try JSONDecoder.memWatchCleanup.decode([CleanupHistoryEntry].self, from: data)
            return entries.sorted { $0.timestamp > $1.timestamp }
        } catch {
            throw CleanupPersistenceError.malformed(fileURL)
        }
    }

    @discardableResult
    func append(report: CleanupExecutionReport) throws -> [CleanupHistoryEntry] {
        var entries = try load()
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

    static func disabled() -> CleanupPreferences {
        CleanupPreferences(
            requestedRootPaths: [],
            projectRootPaths: [],
            cleanupEnabled: false,
            privilegedOperationsEnabled: false,
            privateBackendEnabled: false
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
        let requested = try container.decodeIfPresent([String].self, forKey: .requestedRootPaths)
        let projects = try container.decodeIfPresent([String].self, forKey: .projectRootPaths)
        let cleanup = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled)
        let privileged = try container.decodeIfPresent(Bool.self, forKey: .privilegedOperationsEnabled)
        let privateBackend = try container.decodeIfPresent(Bool.self, forKey: .privateBackendEnabled)
        guard requested != nil && projects != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .cleanupEnabled,
                in: container,
                debugDescription: "Cleanup preferences do not contain both configured root lists"
            )
        }
        requestedRootPaths = requested ?? defaults.requestedRootPaths
        projectRootPaths = projects ?? defaults.projectRootPaths
        cleanupEnabled = cleanup ?? true
        privilegedOperationsEnabled = privileged ?? true
        privateBackendEnabled = privateBackend ?? true
    }
}

actor CleanupPreferencesStore: CleanupPreferencesPersisting {
    private let fileURL: URL

    init(fileURL: URL = CleanupPersistencePaths.preferencesFile) {
        self.fileURL = fileURL
    }

    func load() async throws -> CleanupPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaults()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CleanupPersistenceError.unreadable(fileURL)
        }
        do {
            let value = try JSONDecoder.memWatchCleanup.decode(CleanupPreferences.self, from: data)
            guard value.requestedRootPaths.allSatisfy(Self.isAbsolutePath),
                  value.projectRootPaths.allSatisfy(Self.isAbsolutePath) else {
                throw CleanupPersistenceError.malformed(fileURL)
            }
            return value
        } catch {
            if let error = error as? CleanupPersistenceError { throw error }
            throw CleanupPersistenceError.malformed(fileURL)
        }
    }

    func save(_ preferences: CleanupPreferences) async throws {
        guard preferences.requestedRootPaths.allSatisfy(Self.isAbsolutePath),
              preferences.projectRootPaths.allSatisfy(Self.isAbsolutePath) else {
            throw CleanupPersistenceError.malformed(fileURL)
        }
        try CleanupPersistencePaths.ensureDirectory()
        let data = try JSONEncoder.memWatchCleanup.encode(preferences)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && path.hasPrefix("/")
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
