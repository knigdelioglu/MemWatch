import Foundation

struct PrivilegedHelperInstallerPaths: Equatable, Sendable {
    let helperSourcePath: String
    let plistSourcePath: String
    let authorizationManifestSourcePath: String
    let installedHelperPath: String
    let installedPlistPath: String
    let installedAuthorizationManifestPath: String
    let authorizationDirectoryPath: String
    let daemonLabel: String

    init(
        helperSourcePath: String,
        plistSourcePath: String,
        authorizationManifestSourcePath: String,
        installedHelperPath: String,
        installedPlistPath: String,
        installedAuthorizationManifestPath: String,
        authorizationDirectoryPath: String,
        daemonLabel: String
    ) {
        self.helperSourcePath = helperSourcePath
        self.plistSourcePath = plistSourcePath
        self.authorizationManifestSourcePath = authorizationManifestSourcePath
        self.installedHelperPath = installedHelperPath
        self.installedPlistPath = installedPlistPath
        self.installedAuthorizationManifestPath = installedAuthorizationManifestPath
        self.authorizationDirectoryPath = authorizationDirectoryPath
        self.daemonLabel = daemonLabel
    }
}

enum PrivilegedHelperInstallerScript {
    static func installCommand(paths: PrivilegedHelperInstallerPaths) -> String {
        [
            "set -e",
            runStepFunction,
            optionalBootoutCommand(label: paths.daemonLabel),
            "run_step 'HelperTools dizini' /bin/mkdir -p \(shellQuote("/Library/PrivilegedHelperTools"))",
            "run_step 'Authorization dizini' /bin/mkdir -p \(shellQuote(paths.authorizationDirectoryPath))",
            "run_step 'Authorization dizini izinleri' /bin/chmod 755 \(shellQuote(paths.authorizationDirectoryPath))",
            "run_step 'Authorization dizini sahibi' /usr/sbin/chown root:wheel \(shellQuote(paths.authorizationDirectoryPath))",
            "run_step 'Helper kopyalandı' /usr/bin/install -o root -g wheel -m 755 \(shellQuote(paths.helperSourcePath)) \(shellQuote(paths.installedHelperPath))",
            "run_step 'LaunchDaemon plist kuruldu' /usr/bin/install -o root -g wheel -m 644 \(shellQuote(paths.plistSourcePath)) \(shellQuote(paths.installedPlistPath))",
            "run_step 'Authorization manifest kuruldu' /usr/bin/install -o root -g wheel -m 644 \(shellQuote(paths.authorizationManifestSourcePath)) \(shellQuote(paths.installedAuthorizationManifestPath))",
            "run_step 'launchctl bootstrap' /bin/launchctl bootstrap system \(shellQuote(paths.installedPlistPath))",
            "run_step 'launchctl enable' /bin/launchctl enable \(shellQuote("system/\(paths.daemonLabel)"))"
        ].joined(separator: "\n")
    }

    static func uninstallCommand(paths: PrivilegedHelperInstallerPaths) -> String {
        [
            "set -e",
            runStepFunction,
            optionalBootoutCommand(label: paths.daemonLabel),
            "run_step 'LaunchDaemon plist kaldırıldı' /bin/rm -f \(shellQuote(paths.installedPlistPath))",
            "run_step 'Helper kaldırıldı' /bin/rm -f \(shellQuote(paths.installedHelperPath))",
            "run_step 'Authorization manifest kaldırıldı' /bin/rm -f \(shellQuote(paths.installedAuthorizationManifestPath))"
        ].joined(separator: "\n")
    }

    static let runStepFunction = """
    run_step() {
        step="$1"
        shift
        if output="$("$@" 2>&1)"; then
            printf '%s: OK\\n' "$step"
            if [ -n "$output" ]; then
                printf '%s output: %s\\n' "$step" "$output"
            fi
        else
            status=$?
            printf '%s: FAILED\\n' "$step" >&2
            if [ -n "$output" ]; then
                printf '%s stderr: %s\\n' "$step" "$output" >&2
            else
                printf '%s stderr: <no output>\\n' "$step" >&2
            fi
            return "$status"
        fi
    }
    """

    private static func optionalBootoutCommand(label: String) -> String {
        """
        if output=$(/bin/launchctl bootout \(shellQuote("system/\(label)")) 2>&1); then
            printf 'launchctl bootout: OK\\n'
        elif [ -n "$output" ]; then
            printf 'launchctl bootout: skipped (%s)\\n' "$output"
        else
            printf 'launchctl bootout: skipped (not loaded)\\n'
        fi
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
