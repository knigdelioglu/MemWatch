import AppKit
import Darwin
import Foundation

struct ProcessIdentity: Equatable {
    let startTime: ProcessStartTime
    let userID: uid_t
    let executablePath: String?
}

enum ProcessQuitServiceError: Error, Equatable, LocalizedError {
    case protectedProcess
    case identityUnavailable
    case processNotRunning
    case processChanged
    case processOwnedByAnotherUser
    case applicationUnavailable
    case requestRejected
    case quitTimedOut
    case relaunchFailed
    case signalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .protectedProcess:
            return "MemWatch and protected macOS processes can’t be quit here."
        case .identityUnavailable:
            return "Process details are unavailable. Refresh the list and try again."
        case .processNotRunning:
            return "This process has already exited. The list is being refreshed."
        case .processChanged:
            return "This process changed since the list was updated. Refresh and try again."
        case .processOwnedByAnotherUser:
            return "This process belongs to another user and can’t be quit from MemWatch."
        case .applicationUnavailable:
            return "macOS no longer recognizes this application. Refresh and try again."
        case .requestRejected:
            return "macOS could not send the quit request."
        case .quitTimedOut:
            return "Uygulama kapanmadı. Açık bir kaydetme penceresi olabilir; onu tamamlayıp tekrar dene."
        case .relaunchFailed:
            return "Uygulama kapatıldı ama yeniden açılamadı. Dock veya Launchpad'den açabilirsin."
        case .signalFailed(let code):
            return "The quit request failed: \(String(cString: strerror(code)))."
        }
    }
}

@MainActor
enum ProcessQuitService {
    static func unavailabilityMessage(for process: ProcessMemorySnapshot) -> String? {
        guard process.pid > 1,
              process.pid != getpid() else {
            return ProcessQuitServiceError.protectedProcess.localizedDescription
        }
        guard process.processStartTime != nil else {
            return ProcessQuitServiceError.identityUnavailable.localizedDescription
        }

        switch process.groupKind {
        case .application:
            guard process.bundleIdentifier != nil || process.executablePath != nil else {
                return ProcessQuitServiceError.identityUnavailable.localizedDescription
            }
        case .standalone:
            guard let path = process.executablePath else {
                return ProcessQuitServiceError.identityUnavailable.localizedDescription
            }
            guard !isProtectedSystemProcess(name: process.name, path: path) else {
                return ProcessQuitServiceError.protectedProcess.localizedDescription
            }
        }

        return nil
    }

    static func requestQuit(for process: ProcessMemorySnapshot) throws {
        guard process.pid > 1,
              process.pid != getpid() else {
            throw ProcessQuitServiceError.protectedProcess
        }

        guard let expectedStartTime = process.processStartTime else {
            throw ProcessQuitServiceError.identityUnavailable
        }

        guard let currentIdentity = currentProcessIdentity(for: process.pid) else {
            throw ProcessQuitServiceError.processNotRunning
        }
        guard currentIdentity.startTime == expectedStartTime else {
            throw ProcessQuitServiceError.processChanged
        }
        guard currentIdentity.userID == getuid() else {
            throw ProcessQuitServiceError.processOwnedByAnotherUser
        }

        switch process.groupKind {
        case .application:
            try requestApplicationQuit(for: process, identity: currentIdentity)
        case .standalone:
            try requestStandaloneQuit(for: process, identity: currentIdentity)
        }
    }

    /// macOS system helpers that are safe to terminate because the system
    /// starts them again automatically when they are needed (the wallpaper
    /// service relaunches its extensions and launchd keeps the agent alive).
    /// Everything else under /System stays protected.
    static let autoRelaunchingSystemProcesses: Set<String> = [
        "wallpaperimageextension",
        "wallpapervideoextension",
        "wallpaperagent"
    ]

    static func isAutoRelaunchingSystemProcess(name: String, path: String?) -> Bool {
        let candidates = [name, path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""]
        return candidates.contains { autoRelaunchingSystemProcesses.contains($0.lowercased()) }
    }

    /// GUI applications with a bundle are quit and reopened; allow-listed
    /// system helpers are terminated and macOS restarts them itself.
    static func canRestart(_ process: ProcessMemorySnapshot) -> Bool {
        guard unavailabilityMessage(for: process) == nil else { return false }
        switch process.groupKind {
        case .application:
            return NSRunningApplication(processIdentifier: process.pid)?.bundleURL != nil
        case .standalone:
            return isAutoRelaunchingSystemProcess(name: process.name, path: process.executablePath)
        }
    }

    /// Quits the application normally (it can still ask to save documents),
    /// waits until macOS has fully released it and opens it again. Its
    /// compressed and swapped memory is freed when the old process exits.
    @MainActor
    static func restartApplication(
        _ process: ProcessMemorySnapshot,
        timeout: TimeInterval = 20
    ) async throws {
        if process.groupKind == .standalone,
           isAutoRelaunchingSystemProcess(name: process.name, path: process.executablePath) {
            // macOS relaunches these helpers on demand; just stop the old
            // instance so its compressed/swapped memory is released.
            try requestQuit(for: process)
            let deadline = Date().addingTimeInterval(10)
            while isSameProcessRunning(process) {
                guard Date() < deadline else {
                    throw ProcessQuitServiceError.quitTimedOut
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            return
        }

        guard process.groupKind == .application,
              let runningApplication = NSRunningApplication(processIdentifier: process.pid),
              let bundleURL = runningApplication.bundleURL else {
            throw ProcessQuitServiceError.applicationUnavailable
        }
        let bundleIdentifier = runningApplication.bundleIdentifier ?? process.bundleIdentifier
        let oldPID = process.pid

        try requestQuit(for: process)

        // 1. Wait for the process itself to exit.
        let deadline = Date().addingTimeInterval(timeout)
        while isSameProcessRunning(process) {
            guard Date() < deadline else {
                throw ProcessQuitServiceError.quitTimedOut
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        // 2. Wait until LaunchServices no longer lists the old instance.
        //    Opening the app while it is still registered as "terminating"
        //    makes macOS return the dying instance instead of launching a new
        //    one, which is why the app previously did not come back.
        let launchServicesDeadline = Date().addingTimeInterval(5)
        while Date() < launchServicesDeadline,
              runningApplication.isTerminated == false
                || isRegisteredInstanceAlive(bundleIdentifier: bundleIdentifier, pid: oldPID) {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await Task.sleep(nanoseconds: 500_000_000)

        // 3. Relaunch in the foreground so the user can see it came back.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        } catch {
            // Fall through to verification and the `open` fallback below.
        }

        // 4. Verify a new instance exists; otherwise retry with /usr/bin/open.
        if try await waitForNewInstance(bundleIdentifier: bundleIdentifier, oldPID: oldPID, seconds: 4) {
            return
        }
        try launchWithOpenCommand(bundleURL: bundleURL)
        if try await waitForNewInstance(bundleIdentifier: bundleIdentifier, oldPID: oldPID, seconds: 6) {
            return
        }
        throw ProcessQuitServiceError.relaunchFailed
    }

    private static func isRegisteredInstanceAlive(bundleIdentifier: String?, pid: Int32) -> Bool {
        guard let bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier == pid && !$0.isTerminated }
    }

    @MainActor
    private static func waitForNewInstance(
        bundleIdentifier: String?,
        oldPID: Int32,
        seconds: TimeInterval
    ) async throws -> Bool {
        guard let bundleIdentifier else {
            // Without a bundle identifier we cannot verify; assume success.
            return true
        }
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let relaunched = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .contains { $0.processIdentifier != oldPID && !$0.isTerminated }
            if relaunched { return true }
            try await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline
        return false
    }

    private static func launchWithOpenCommand(bundleURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [bundleURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func isSameProcessRunning(_ process: ProcessMemorySnapshot) -> Bool {
        guard let expectedStartTime = process.processStartTime,
              let currentIdentity = currentProcessIdentity(for: process.pid) else {
            return false
        }
        return currentIdentity.startTime == expectedStartTime
            && currentIdentity.userID == getuid()
    }

    static func currentProcessIdentity(for pid: Int32) -> ProcessIdentity? {
        guard pid > 0 else { return nil }

        var info = proc_taskallinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskallinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, pointer, expectedSize)
        }
        guard result == expectedSize else { return nil }

        return ProcessIdentity(
            startTime: ProcessStartTime(
                seconds: Int64(info.pbsd.pbi_start_tvsec),
                microseconds: Int64(info.pbsd.pbi_start_tvusec)
            ),
            userID: info.pbsd.pbi_uid,
            executablePath: executablePath(for: pid)
        )
    }

    private static func requestApplicationQuit(
        for process: ProcessMemorySnapshot,
        identity: ProcessIdentity
    ) throws {
        guard let application = NSRunningApplication(processIdentifier: process.pid),
              !application.isTerminated else {
            throw ProcessQuitServiceError.applicationUnavailable
        }

        if let bundleIdentifier = process.bundleIdentifier {
            guard application.bundleIdentifier == bundleIdentifier else {
                throw ProcessQuitServiceError.processChanged
            }
        } else if let expectedPath = process.executablePath,
                  let currentPath = identity.executablePath {
            guard standardizedPath(expectedPath) == standardizedPath(currentPath) else {
                throw ProcessQuitServiceError.processChanged
            }
        } else {
            throw ProcessQuitServiceError.identityUnavailable
        }

        guard application.terminate() else {
            throw ProcessQuitServiceError.requestRejected
        }
    }

    private static func requestStandaloneQuit(
        for process: ProcessMemorySnapshot,
        identity: ProcessIdentity
    ) throws {
        guard let expectedPath = process.executablePath,
              let currentPath = identity.executablePath else {
            throw ProcessQuitServiceError.identityUnavailable
        }
        guard standardizedPath(expectedPath) == standardizedPath(currentPath) else {
            throw ProcessQuitServiceError.processChanged
        }
        guard !isProtectedSystemProcess(name: process.name, path: currentPath, resolveSymlinks: true) else {
            throw ProcessQuitServiceError.protectedProcess
        }

        guard kill(process.pid, SIGTERM) == 0 else {
            if errno == ESRCH {
                throw ProcessQuitServiceError.processNotRunning
            }
            if errno == EPERM {
                throw ProcessQuitServiceError.processOwnedByAnotherUser
            }
            throw ProcessQuitServiceError.signalFailed(errno)
        }
    }

    private static func isProtectedSystemProcess(
        name: String,
        path: String,
        resolveSymlinks: Bool = false
    ) -> Bool {
        let protectedNames: Set<String> = [
            "kernel_task",
            "launchd",
            "loginwindow",
            "windowserver"
        ]
        guard !protectedNames.contains(name.lowercased()) else { return true }

        let path = resolveSymlinks
            ? standardizedPath(path)
            : URL(fileURLWithPath: path).standardizedFileURL.path
        let pathLowercased = path.lowercased()

        // Explicit, small allow-list of helpers macOS restarts by itself.
        // Checked on the real executable name and location so a renamed copy
        // elsewhere cannot borrow the exemption.
        let executableName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if autoRelaunchingSystemProcesses.contains(executableName),
           pathLowercased.hasPrefix("/system/") {
            return false
        }

        let protectedRoots = [
            "/system/",
            "/bin/",
            "/sbin/",
            "/usr/bin/",
            "/usr/sbin/",
            "/usr/libexec/"
        ]
        return protectedRoots.contains(where: pathLowercased.hasPrefix)
    }

    private static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(pid, pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
