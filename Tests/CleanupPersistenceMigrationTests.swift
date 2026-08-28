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
    static func main() throws {
        try testLegacyPreferences()
        try testCurrentPreferencesRoundTrip()
        try testLegacyTrashHistoryMigration()
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
}
