import Foundation

struct LegacyAmbientSyncProcessResult: Sendable {
    let terminationStatus: Int32?
    let launchError: String?

    var succeeded: Bool { terminationStatus == 0 && launchError == nil }
}

protocol LegacyAmbientSyncProcessRunning: Sendable {
    func run(executableURL: URL, arguments: [String]) async -> LegacyAmbientSyncProcessResult
}

struct SystemLegacyAmbientSyncProcessRunner: LegacyAmbientSyncProcessRunning {
    func run(executableURL: URL, arguments: [String]) async -> LegacyAmbientSyncProcessResult {
        let path = executableURL.path
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            // Migration diagnostics are represented by the exit status. Avoid
            // pipe back-pressure while the detached runner waits for launchctl.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                return LegacyAmbientSyncProcessResult(
                    terminationStatus: process.terminationStatus,
                    launchError: nil
                )
            } catch {
                return LegacyAmbientSyncProcessResult(
                    terminationStatus: nil,
                    launchError: error.localizedDescription
                )
            }
        }.value
    }
}

enum LegacyAmbientSyncMigrationResult: Equatable, Sendable {
    case alreadyCompleted
    case noLegacyPlist
    case completed
    case conflict(String)
    case failed(String)

    var completedSuccessfully: Bool {
        switch self {
        case .alreadyCompleted, .noLegacyPlist, .completed:
            return true
        case .conflict, .failed:
            return false
        }
    }
}

enum LegacyAmbientSyncMigration {
    private static let versionKey = "MemWatch.LegacyAmbientSyncCleanupVersion"
    private static let currentVersion = 1
    private static let legacyLabel = "fyi.kadir.AmbientSync"
    @MainActor private static var migrationInFlight = false
    @MainActor private static var scheduledTask: Task<LegacyAmbientSyncMigrationResult, Never>?

    /// Schedules the one-shot migration without making app construction wait
    /// for launchctl. Callers share the same task so cleanup is still
    /// serialized, while the display runtime decides how to handle the result.
    @MainActor
    @discardableResult
    static func scheduleIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        runner: LegacyAmbientSyncProcessRunning = SystemLegacyAmbientSyncProcessRunner()
    ) -> Task<LegacyAmbientSyncMigrationResult, Never>? {
        if let scheduledTask {
            return scheduledTask
        }
        guard defaults.integer(forKey: versionKey) < currentVersion, !migrationInFlight else { return nil }
        migrationInFlight = true

        // The common case is that the legacy agent has already been removed.
        // Complete that case synchronously so display runtime startup cannot
        // remain behind an unnecessary task boundary or stale migration wait.
        let launchAgentURL = homeDirectory
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(legacyLabel).plist")
        guard fileManager.fileExists(atPath: launchAgentURL.path) else {
            defaults.set(currentVersion, forKey: versionKey)
            migrationInFlight = false
            return nil
        }

        let task = Task {
            let result = await runIfNeeded(defaults: defaults, fileManager: fileManager, homeDirectory: homeDirectory, runner: runner)
            if case .failed(let reason) = result {
                print("[LegacyAmbientSyncMigration] cleanup failed: \(reason)")
            } else {
                print("[LegacyAmbientSyncMigration] cleanup result: \(result)")
            }
            migrationInFlight = false
            scheduledTask = nil
            return result
        }
        scheduledTask = task
        return task
    }

    @MainActor
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        runner: LegacyAmbientSyncProcessRunning = SystemLegacyAmbientSyncProcessRunner()
    ) async -> LegacyAmbientSyncMigrationResult {
        guard defaults.integer(forKey: versionKey) < currentVersion else {
            return .alreadyCompleted
        }

        let launchAgentURL = homeDirectory
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(legacyLabel).plist")

        guard fileManager.fileExists(atPath: launchAgentURL.path) else {
            defaults.set(currentVersion, forKey: versionKey)
            return .noLegacyPlist
        }

        let serviceTarget = "gui/\(getuid())/\(legacyLabel)"
        let serviceState = await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/launchctl"),
            arguments: ["print", serviceTarget]
        )

        if serviceState.succeeded {
            let bootoutResult = await runner.run(
                executableURL: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["bootout", serviceTarget]
            )

            if !bootoutResult.succeeded {
                // bootout can fail after the service has already disappeared
                // (or while launchd is finishing the unload). Probe again
                // before deciding that another AmbientSync controller is
                // actually still active.
                let remainingService = await runner.run(
                    executableURL: URL(fileURLWithPath: "/bin/launchctl"),
                    arguments: ["print", serviceTarget]
                )
                if remainingService.succeeded {
                    return .conflict("legacy AmbientSync service is still loaded after bootout failed")
                }
                if let launchError = remainingService.launchError {
                    return .failed("legacy AmbientSync service state could not be verified: \(launchError)")
                }
            }
        } else if let launchError = serviceState.launchError {
            // A launchctl launch error is different from its normal non-zero
            // "service not found" result. Keep the plist for a later retry,
            // but never make this infrastructure problem disable Display.
            return .failed("legacy AmbientSync service state could not be inspected: \(launchError)")
        }

        do {
            try fileManager.removeItem(at: launchAgentURL)
            defaults.set(currentVersion, forKey: versionKey)
            return .completed
        } catch {
            return .failed("legacy plist removal failed: \(error.localizedDescription)")
        }
    }
}
