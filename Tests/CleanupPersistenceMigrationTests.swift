import Foundation

// Standalone CI shim. The migration test only needs the execution result/report
// model declarations from CleanupDeletionEngine, not a live privileged XPC client.
struct PrivilegedHelperClient: Sendable {
    init() {}

    func execute(_ request: PrivilegedOperationRequest) async throws -> PrivilegedOperationResponse {
        throw NSError(
            domain: "CleanupPersistenceMigrationTests",
            code: 999,
            userInfo: [NSLocalizedDescriptionKey: "Privileged helper must not be reached by persistence migration tests"]
        )
    }
}

@main
struct CleanupPersistenceMigrationTests {
    static func main() async throws {
        try testLegacyPreferences()
        try testCurrentPreferencesRoundTrip()
        try testLegacyTrashHistoryMigration()
        try await testCorruptStateFailsClosed()
        try await testIgnorePathScopePreserved()
        try await testMalformedIgnoreRuleFailsClosed()
        try await testEmptyPreferencesFailClosed()
        print("PASS Cleanup persistence migration")
    }

    private static func testLegacyPreferences() throws {
        let legacyPreferences = """
        {
          "requestedRootPaths": ["/tmp/legacy-files"],
          "projectRootPaths": ["/tmp/legacy-projects"],
          "privateBackendEnabled": false
        }
        """.data(using: .utf8)!

        let migrated = try JSONDecoder().decode(CleanupPreferences.self, from: legacyPreferences)
        precondition(migrated.requestedRootPaths == ["/tmp/legacy-files"], "Legacy file roots must be preserved")
        precondition(migrated.projectRootPaths == ["/tmp/legacy-projects"], "Legacy project roots must be preserved")
        precondition(migrated.cleanupEnabled, "New cleanup master switch should default on for a legacy schema")
        precondition(migrated.privilegedOperationsEnabled, "New privileged switch should default on for a legacy schema")
        precondition(!migrated.privateBackendEnabled, "Existing private-backend preference must be preserved")
    }

    private static func testCurrentPreferencesRoundTrip() throws {
        let current = CleanupPreferences(
            requestedRootPaths: ["/tmp/files"],
            projectRootPaths: ["/tmp/projects"],
            cleanupEnabled: false,
            privilegedOperationsEnabled: false,
            privateBackendEnabled: false
        )
        let encoded = try JSONEncoder().encode(current)
        let roundTrip = try JSONDecoder().decode(CleanupPreferences.self, from: encoded)
        precondition(roundTrip == current, "Current cleanup preferences must round-trip without loss")
    }

    private static func testLegacyTrashHistoryMigration() throws {
        let entryID = "00000000-0000-0000-0000-000000000001"
        let resultID = "00000000-0000-0000-0000-000000000002"
        let candidateID = "00000000-0000-0000-0000-000000000003"
        let legacyHistory = """
        {
          "id": "\(entryID)",
          "timestamp": "2026-08-28T10:00:00Z",
          "mode": "apply",
          "requestedCount": 1,
          "successfulCount": 1,
          "failedCount": 0,
          "reclaimedBytes": 4096,
          "results": [
            {
              "id": "\(resultID)",
              "candidateID": "\(candidateID)",
              "ruleID": "largeold.file",
              "path": "/tmp/legacy-trash-item",
              "displayName": "legacy-trash-item",
              "status": "movedToTrash",
              "reclaimedBytes": 4096,
              "message": "Moved to Trash and verified."
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(CleanupHistoryEntry.self, from: legacyHistory)
        precondition(migrated.reclaimedBytes == 0, "Legacy Trash moves must not remain counted as immediate reclaimed space")
        precondition(migrated.movedToTrashBytes == 4096, "Legacy Trash bytes should migrate to affected Trash bytes")
        precondition(migrated.results.count == 1)
        precondition(migrated.results[0].affectedBytes == 4096)
        precondition(migrated.results[0].reclaimedBytes == 0)
    }

    private static func testCorruptStateFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemWatchPersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let invalid = Data("{not-json".utf8)
        let ignoreURL = root.appendingPathComponent("ignore.json")
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let historyURL = root.appendingPathComponent("history.json")
        try invalid.write(to: ignoreURL)
        try invalid.write(to: preferencesURL)
        try invalid.write(to: historyURL)

        do {
            _ = try await CleanupIgnoreStore(fileURL: ignoreURL).load()
            preconditionFailure("Corrupt ignore state must not be treated as an empty ignore list")
        } catch CleanupPersistenceError.malformed {
        }
        do {
            _ = try await CleanupPreferencesStore(fileURL: preferencesURL).load()
            preconditionFailure("Corrupt preferences must not silently enable cleanup")
        } catch CleanupPersistenceError.malformed {
        }
        do {
            _ = try await CleanupHistoryStore(fileURL: historyURL).load()
            preconditionFailure("Corrupt history must not be treated as an empty history")
        } catch CleanupPersistenceError.malformed {
        }
    }

    private static func testIgnorePathScopePreserved() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemWatchIgnore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CleanupIgnoreStore(fileURL: url)
        try await store.save([
            CleanupIgnoreRule(kind: .path, value: "/tmp/exact-target", recursive: false),
            CleanupIgnoreRule(kind: .path, value: "/tmp/recursive-target", recursive: true)
        ])
        let snapshot = try await store.snapshot()
        precondition(snapshot.exactPathValues.contains("/tmp/exact-target"))
        precondition(!snapshot.pathValues.contains("/tmp/exact-target"))
        precondition(snapshot.pathValues.contains("/tmp/recursive-target"))
    }

    private static func testMalformedIgnoreRuleFailsClosed() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemWatchMalformedIgnore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CleanupIgnoreStore(fileURL: url)
        try await store.save([CleanupIgnoreRule(kind: .category, value: "not-a-real-category")])
        do {
            _ = try await store.snapshot()
            preconditionFailure("Malformed ignore values must not be silently ignored")
        } catch CleanupPersistenceError.malformed {
        }
    }

    private static func testEmptyPreferencesFailClosed() async throws {
        let decoder = JSONDecoder()
        do {
            _ = try decoder.decode(CleanupPreferences.self, from: Data("{}".utf8))
            preconditionFailure("An empty preferences object must not enable cleanup")
        } catch DecodingError.dataCorrupted {
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemWatchRelativePreferences-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CleanupPreferencesStore(fileURL: url)
        let invalid = """
        {
          "requestedRootPaths": ["relative/path"],
          "projectRootPaths": ["/tmp/projects"],
          "cleanupEnabled": true,
          "privilegedOperationsEnabled": false,
          "privateBackendEnabled": false
        }
        """
        try Data(invalid.utf8).write(to: url)
        do {
            _ = try await store.load()
            preconditionFailure("Relative persisted roots must fail closed")
        } catch CleanupPersistenceError.malformed {
        }
    }
}
