import Foundation

@main
struct CleanupPersistenceMigrationTests {
    static func main() throws {
        let legacyPreferences = """
        {
          "requestedRootPaths": ["/tmp/legacy-files"],
          "projectRootPaths": ["/tmp/legacy-projects"],
          "privateBackendEnabled": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let migrated = try decoder.decode(CleanupPreferences.self, from: legacyPreferences)
        precondition(migrated.requestedRootPaths == ["/tmp/legacy-files"], "Legacy file roots must be preserved")
        precondition(migrated.projectRootPaths == ["/tmp/legacy-projects"], "Legacy project roots must be preserved")
        precondition(migrated.cleanupEnabled, "New cleanup master switch should default on for a legacy schema")
        precondition(migrated.privilegedOperationsEnabled, "New privileged switch should default on for a legacy schema")
        precondition(!migrated.privateBackendEnabled, "Existing private-backend preference must be preserved")

        let current = CleanupPreferences(
            requestedRootPaths: ["/tmp/files"],
            projectRootPaths: ["/tmp/projects"],
            cleanupEnabled: false,
            privilegedOperationsEnabled: false,
            privateBackendEnabled: false
        )
        let encoded = try JSONEncoder().encode(current)
        let roundTrip = try decoder.decode(CleanupPreferences.self, from: encoded)
        precondition(roundTrip == current, "Current cleanup preferences must round-trip without loss")

        print("PASS Cleanup persistence migration")
    }
}
