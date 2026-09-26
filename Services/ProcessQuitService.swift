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
