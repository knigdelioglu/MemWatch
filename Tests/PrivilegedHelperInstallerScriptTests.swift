import Foundation

@main
struct PrivilegedHelperInstallerScriptTests {
    static func main() throws {
        let paths = PrivilegedHelperInstallerPaths(
            helperSourcePath: "/tmp/Mem Watch/helper",
            plistSourcePath: "/tmp/Mem Watch/helper.plist",
            authorizationManifestSourcePath: "/tmp/Mem Watch/authorization.plist",
            installedHelperPath: "/Library/PrivilegedHelperTools/MemWatchPrivilegedHelper",
            installedPlistPath: "/Library/LaunchDaemons/com.knigdelioglu.MemWatch.PrivilegedHelper.plist",
            installedAuthorizationManifestPath: "/Library/Application Support/MemWatch/PrivilegedHelperAuthorization.plist",
            authorizationDirectoryPath: "/Library/Application Support/MemWatch",
            daemonLabel: "com.knigdelioglu.MemWatch.PrivilegedHelper"
        )

        let install = PrivilegedHelperInstallerScript.installCommand(paths: paths)
        let uninstall = PrivilegedHelperInstallerScript.uninstallCommand(paths: paths)

        precondition(install.hasPrefix("set -e\n"), "install must fail fast")
        precondition(uninstall.hasPrefix("set -e\n"), "uninstall must fail fast")
        for step in [
            "Helper kopyalandı",
            "LaunchDaemon plist kuruldu",
            "Authorization manifest kuruldu",
            "launchctl bootstrap",
            "launchctl enable"
        ] {
            precondition(install.contains("run_step '\(step)'"), "\(step) must be a checked step")
        }
        precondition(install.contains("launchctl bootstrap") && install.contains("2>&1"), "bootstrap diagnostics must be captured")
        precondition(install.contains("printf '%s stderr: %s\\n'"), "failed steps must report stderr")
        precondition(install.contains("launchctl bootstrap: skipped") == false, "bootstrap must not be optional")
        precondition(install.contains("'/tmp/Mem Watch/helper'"), "paths must be shell quoted")

        try assertShellSyntax(install)
        try assertShellSyntax(uninstall)
        try assertFailureIsReportedAndStopsExecution()

        print("PASS Privileged helper installer script")
    }

    private static func assertShellSyntax(_ script: String) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memwatch-installer-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: url) }
        try script.write(to: url, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", url.path]
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "generated installer script must pass sh -n")
    }

    private static func assertFailureIsReportedAndStopsExecution() throws {
        let script = [
            "set -e",
            PrivilegedHelperInstallerScript.runStepFunction,
            "run_step 'bootstrap probe' /bin/sh -c 'printf probe-error >&2; exit 7'",
            "printf 'unexpected success\\n'"
        ].joined(separator: "\n")

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        precondition(process.terminationStatus != 0, "a failed installer step must fail the script")
        precondition(output.contains("bootstrap probe: FAILED"), "failed step name must be reported")
        precondition(output.contains("probe-error"), "failed step stderr must be reported")
    }
}
