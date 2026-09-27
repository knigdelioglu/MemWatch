import Foundation

@main
struct MoleCleanupServiceTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemWatchMoleService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let argumentLog = root.appendingPathComponent("arguments.txt")
        let workingCLI = root.appendingPathComponent("mo")
        try writeCLI(
            at: workingCLI,
            body: "printf '%s\\n' \"$@\" > \(shellQuoted(argumentLog.path))\nprintf '\\033[32mFixture cleanup output\\033[0m\\n'\n"
        )

        let service = MoleCleanupService(executablePath: workingCLI.path)
        service.runCleanup()
        service.runCleanup()
        try await waitForCompletion(of: service)

        guard case .finished(.clean, exitStatus: 0) = service.phase else {
            preconditionFailure("Mole clean should report its zero exit status")
        }
        precondition(service.output.contains("Fixture cleanup output"), "ANSI formatting should be removed from captured output")
        let capturedArguments = try String(contentsOf: argumentLog, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(capturedArguments == "clean", "Repeated clicks must not launch duplicate clean processes")

        let failingCLI = root.appendingPathComponent("mo-fail")
        try writeCLI(at: failingCLI, body: "printf 'fixture failure\\n' >&2\nexit 7\n")
        let failingService = MoleCleanupService(executablePath: failingCLI.path)
        failingService.runCleanup()
        try await waitForCompletion(of: failingService)
        guard case .finished(.clean, exitStatus: 7) = failingService.phase else {
            preconditionFailure("Mole's non-zero exit status should remain visible")
        }
        precondition(failingService.output.contains("fixture failure"), "Standard error should be shown in the result")

        let missingService = MoleCleanupService(executablePath: nil)
        missingService.runCleanup()
        guard case .unavailable = missingService.phase else {
            preconditionFailure("A missing Mole executable should be reported as unavailable")
        }

        let launchFailureService = MoleCleanupService(executablePath: root.appendingPathComponent("missing-mo").path)
        launchFailureService.runCleanup()
        try await waitForCompletion(of: launchFailureService)
        guard case .failed(.clean, _) = launchFailureService.phase else {
            preconditionFailure("A process launch error should not appear as successful cleanup")
        }

        print("PASS Mole cleanup process, output, duplicate-run, and failure handling")
    }

    @MainActor
    private static func waitForCompletion(of service: MoleCleanupService) async throws {
        let deadline = Date().addingTimeInterval(5)
        while service.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if service.isRunning {
            preconditionFailure("Mole test process timed out; phase=\(service.phase)")
        }
    }

    private static func writeCLI(at url: URL, body: String) throws {
        let script = "#!/bin/sh\n\(body)"
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
