import Foundation

enum LegacyAmbientSyncMigration {
    private static let versionKey = "MemWatch.LegacyAmbientSyncCleanupVersion"
    private static let currentVersion = 1
    private static let legacyLabel = "fyi.kadir.AmbientSync"

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        defer { defaults.set(currentVersion, forKey: versionKey) }

        let launchAgentURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(legacyLabel).plist")

        guard fileManager.fileExists(atPath: launchAgentURL.path) else { return }

        // Unload only the exact legacy label owned by AmbientSync. A failed
        // unload is non-fatal; removing the known plist prevents it from
        // starting again on the next login.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(legacyLabel)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // A missing or unavailable launchctl must not block app startup.
        }

        try? fileManager.removeItem(at: launchAgentURL)
    }
}
