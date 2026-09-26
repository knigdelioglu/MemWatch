import AppKit
import Darwin
import Foundation

@main
@MainActor
enum ProcessQuitServiceTests {
    static func main() throws {
        if CommandLine.arguments.contains("--quit-child") {
            while true {
                _ = Darwin.sleep(60)
            }
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--quit-child"]
        try child.run()

        defer {
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
        }

        let pid = Int32(child.processIdentifier)
        guard let identity = ProcessQuitService.currentProcessIdentity(for: pid),
              let executablePath = identity.executablePath else {
            fatalError("Could not identify the test child process")
        }

        let staleSnapshot = snapshot(
            pid: pid,
            path: executablePath,
            startTime: ProcessStartTime(
                seconds: identity.startTime.seconds + 1,
                microseconds: identity.startTime.microseconds
            )
        )

        let protectedSnapshot = snapshot(
            pid: 99,
            path: executablePath,
            startTime: identity.startTime,
            name: "WindowServer"
        )
        precondition(
            ProcessQuitService.unavailabilityMessage(for: protectedSnapshot) != nil,
            "Core system processes must not expose an enabled Quit action"
        )

        do {
            try ProcessQuitService.requestQuit(for: staleSnapshot)
            fatalError("A stale PID snapshot must not terminate a process")
        } catch ProcessQuitServiceError.processChanged {
            // Expected: the PID still belongs to the child, but its start time differs.
        }

        guard let selfIdentity = ProcessQuitService.currentProcessIdentity(for: getpid()),
              let selfPath = selfIdentity.executablePath else {
            fatalError("Could not identify the test process")
        }
        do {
            try ProcessQuitService.requestQuit(
                for: snapshot(pid: getpid(), path: selfPath, startTime: selfIdentity.startTime)
            )
            fatalError("MemWatch must never be able to quit its own process")
        } catch ProcessQuitServiceError.protectedProcess {
            // Expected: the current process is explicitly protected.
        }

        let validSnapshot = snapshot(
            pid: pid,
            path: executablePath,
            startTime: identity.startTime
        )
        try ProcessQuitService.requestQuit(for: validSnapshot)
        child.waitUntilExit()
        precondition(child.terminationReason == .uncaughtSignal)
        precondition(child.terminationStatus == Int32(SIGTERM))

        print("Process quit service identity and SIGTERM checks passed")
    }

    private static func snapshot(
        pid: Int32,
        path: String,
        startTime: ProcessStartTime,
        name: String = "process-quit-test-child"
    ) -> ProcessMemorySnapshot {
        ProcessMemorySnapshot(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: path,
            memoryBytes: 1,
            memoryMetric: .physicalFootprint,
            residentBytes: 1,
            residentProcessCount: 1,
            physicalFootprintProcessCount: 1,
            residentFallbackProcessCount: 0,
            processIDs: [pid],
            processStartTime: startTime,
            groupKind: .standalone
        )
    }
}
