import Foundation
import ServiceManagement

enum PrivilegedHelperRegistrationState: String, Sendable {
    case unavailable
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum PrivilegedHelperClientError: LocalizedError {
    case unavailable
    case invalidResponse
    case remote(String)
    case protocolMismatch

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Privileged helper is unavailable."
        case .invalidResponse: return "Privileged helper returned an invalid response."
        case .remote(let message): return message
        case .protocolMismatch: return "Privileged helper protocol version does not match MemWatch."
        }
    }
}

struct PrivilegedHelperClient: Sendable {
    func ping() async throws -> PrivilegedPingResponse {
        try await withConnection { proxy, finish in
            proxy.ping { data in
                finish(Self.decode(PrivilegedPingResponse.self, from: data))
            }
        }
    }

    func scan(ruleIDs: [CleanupRuleID]) async throws -> PrivilegedScanResponse {
        let request = PrivilegedScanRequest(ruleIDs: ruleIDs.map(\.rawValue))
        let data = try JSONEncoder().encode(request)
        return try await withConnection { proxy, finish in
            proxy.scan(data) { responseData in
                finish(Self.decode(PrivilegedScanResponse.self, from: responseData))
            }
        }
    }

    func execute(_ request: PrivilegedOperationRequest) async throws -> PrivilegedOperationResponse {
        let data = try JSONEncoder().encode(request)
        let response: PrivilegedOperationResponse = try await withConnection { proxy, finish in
            proxy.execute(data) { responseData in
                finish(Self.decode(PrivilegedOperationResponse.self, from: responseData))
            }
        }
        guard response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion else {
            throw PrivilegedHelperClientError.protocolMismatch
        }
        guard response.success else {
            throw PrivilegedHelperClientError.remote(response.message)
        }
        return response
    }

    private func withConnection<T: Sendable>(
        _ body: @escaping (MemWatchPrivilegedHelperXPC, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(
                machServiceName: MemWatchPrivilegedHelperConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: MemWatchPrivilegedHelperXPC.self)

            let lock = NSLock()
            var completed = false
            func finish(_ result: Result<T, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !completed else { return }
                completed = true
                connection.invalidate()
                continuation.resume(with: result)
            }

            connection.interruptionHandler = {
                finish(.failure(PrivilegedHelperClientError.unavailable))
            }
            connection.invalidationHandler = {
                lock.lock()
                let shouldFail = !completed
                lock.unlock()
                if shouldFail {
                    finish(.failure(PrivilegedHelperClientError.unavailable))
                }
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                finish(.failure(error))
            }) as? MemWatchPrivilegedHelperXPC else {
                finish(.failure(PrivilegedHelperClientError.unavailable))
                return
            }
            body(proxy, finish)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, Error> {
        do {
            let value = try JSONDecoder().decode(type, from: data)
            if let ping = value as? PrivilegedPingResponse,
               ping.protocolVersion != MemWatchPrivilegedHelperConstants.protocolVersion {
                return .failure(PrivilegedHelperClientError.protocolMismatch)
            }
            if let scan = value as? PrivilegedScanResponse,
               scan.protocolVersion != MemWatchPrivilegedHelperConstants.protocolVersion {
                return .failure(PrivilegedHelperClientError.protocolMismatch)
            }
            return .success(value)
        } catch {
            return .failure(PrivilegedHelperClientError.invalidResponse)
        }
    }
}

private enum PrivilegedHelperCompatibilityError: LocalizedError {
    case bundledHelperMissing
    case bundledDaemonPlistMissing
    case malformedBundledDaemonPlist
    case administratorAuthorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "MemWatch uygulama paketinde yetkili yardımcı bulunamadı."
        case .bundledDaemonPlistMissing:
            return "MemWatch uygulama paketinde LaunchDaemon tanımı bulunamadı."
        case .malformedBundledDaemonPlist:
            return "MemWatch LaunchDaemon tanımı geçersiz veya helper yoluyla eşleşmiyor."
        case .administratorAuthorizationFailed(let message):
            return "Yönetici yetkili yardımcı kurulumu başarısız: \(message)"
        }
    }
}

/// A deliberately narrow fallback for machines where SMAppService cannot locate
/// the bundled LaunchDaemon. It can only install MemWatch's own helper and plist
/// at fixed system locations. There is no arbitrary command/path interface.
private struct PrivilegedHelperCompatibilityInstaller {
    private let fileManager = FileManager.default
    private let label = MemWatchPrivilegedHelperConstants.daemonLabel
    private let plistName = MemWatchPrivilegedHelperConstants.daemonPlistName

    private var installedHelperPath: String {
        "/Library/PrivilegedHelperTools/MemWatchPrivilegedHelper"
    }

    private var installedPlistPath: String {
        "/Library/LaunchDaemons/\(plistName)"
    }

    func bundledResources() throws -> (helper: URL, plist: URL) {
        let bundle = Bundle.main.bundleURL.standardizedFileURL
        let plist = bundle
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(plistName, isDirectory: false)
        guard fileManager.fileExists(atPath: plist.path) else {
            throw PrivilegedHelperCompatibilityError.bundledDaemonPlistMissing
        }

        let object = try? PropertyListSerialization.propertyList(
            from: Data(contentsOf: plist),
            options: [],
            format: nil
        )
        guard let dictionary = object as? [String: Any],
              let bundleProgram = dictionary["BundleProgram"] as? String,
              !bundleProgram.isEmpty else {
            throw PrivilegedHelperCompatibilityError.malformedBundledDaemonPlist
        }

        let declaredHelper = bundle.appendingPathComponent(bundleProgram, isDirectory: false).standardizedFileURL
        let fallbackCandidates = [
            declaredHelper,
            bundle.appendingPathComponent("Contents/Resources/MemWatchPrivilegedHelper"),
            bundle.appendingPathComponent("Contents/Library/HelperTools/MemWatchPrivilegedHelper")
        ]
        guard let helper = fallbackCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            throw PrivilegedHelperCompatibilityError.bundledHelperMissing
        }
        return (helper, plist)
    }

    func install() throws {
        let resources = try bundledResources()
        let temporaryPlist = try makeStandaloneLaunchDaemonPlist()
        defer { try? fileManager.removeItem(at: temporaryPlist) }

        let command = [
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "/usr/bin/install -o root -g wheel -m 755 \(shellQuote(resources.helper.path)) \(shellQuote(installedHelperPath))",
            "/usr/bin/install -o root -g wheel -m 644 \(shellQuote(temporaryPlist.path)) \(shellQuote(installedPlistPath))",
            "/bin/launchctl bootstrap system \(shellQuote(installedPlistPath))",
            "/bin/launchctl enable system/\(label)"
        ].joined(separator: "; ")

        try runWithAdministratorPrivileges(command)
    }

    func uninstall() throws {
        let command = [
            "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "/bin/rm -f \(shellQuote(installedPlistPath))",
            "/bin/rm -f \(shellQuote(installedHelperPath))"
        ].joined(separator: "; ")
        try runWithAdministratorPrivileges(command)
    }

    private func makeStandaloneLaunchDaemonPlist() throws -> URL {
        let dictionary: [String: Any] = [
            "Label": label,
            "Program": installedHelperPath,
            "AssociatedBundleIdentifiers": [MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier],
            "MachServices": [MemWatchPrivilegedHelperConstants.machServiceName: true],
            "RunAtLoad": false,
            "KeepAlive": false,
            "ThrottleInterval": 5
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("memwatch-\(UUID().uuidString)-\(plistName)")
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func runWithAdministratorPrivileges(_ shellCommand: String) throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"
        ]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Bilinmeyen hata"
            throw PrivilegedHelperCompatibilityError.administratorAuthorizationFailed(message)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private enum PrivateCompatibilityPolicy {
    static var isEnabled: Bool {
        guard let data = try? Data(contentsOf: CleanupPersistencePaths.preferencesFile),
              let preferences = try? JSONDecoder().decode(CleanupPreferences.self, from: data) else {
            return CleanupPreferences.defaults().privateBackendEnabled
        }
        return preferences.privateBackendEnabled
    }
}

@MainActor
final class PrivilegedHelperService: ObservableObject {
    @Published private(set) var state: PrivilegedHelperRegistrationState = .unavailable
    @Published private(set) var lastError: String?
    @Published private(set) var compatibilityHelperActive = false

    private let service = SMAppService.daemon(
        plistName: MemWatchPrivilegedHelperConstants.daemonPlistName
    )
    private let compatibilityInstaller = PrivilegedHelperCompatibilityInstaller()
    let client = PrivilegedHelperClient()

    init() {
        refreshStatus()
    }

    var isAvailableForCleanup: Bool {
        state == .enabled || compatibilityHelperActive
    }

    func refreshStatus() {
        switch service.status {
        case .notRegistered:
            state = compatibilityHelperActive ? .enabled : .notRegistered
        case .enabled:
            state = .enabled
        case .requiresApproval:
            state = .requiresApproval
        case .notFound:
            state = compatibilityHelperActive ? .enabled : .notFound
        @unknown default:
            state = compatibilityHelperActive ? .enabled : .unavailable
        }
    }

    func register() {
        lastError = nil

        do {
            _ = try compatibilityInstaller.bundledResources()
        } catch {
            lastError = error.localizedDescription
        }

        do {
            try service.register()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()

        if state == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }

        guard state == .notFound || state == .unavailable else {
            return
        }
        guard PrivateCompatibilityPolicy.isEnabled else {
            if lastError == nil {
                lastError = "SMAppService yardımcıyı bulamadı. Özel uyumluluk yöntemleri kapalı olduğu için alternatif kurulum kullanılmadı."
            }
            return
        }

        do {
            try compatibilityInstaller.install()
            compatibilityHelperActive = true
            state = .enabled
            lastError = nil
        } catch {
            compatibilityHelperActive = false
            lastError = error.localizedDescription
            refreshStatus()
        }
    }

    func unregister() {
        lastError = nil
        do {
            try service.unregister()
        } catch {
            // A compatibility-installed daemon is not registered with SMAppService.
            if !compatibilityHelperActive {
                lastError = error.localizedDescription
            }
        }

        if compatibilityHelperActive {
            do {
                try compatibilityInstaller.uninstall()
                compatibilityHelperActive = false
            } catch {
                lastError = error.localizedDescription
            }
        }
        refreshStatus()
    }

    func verifyConnection() async -> Bool {
        do {
            let response = try await client.ping()
            let verified = response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion &&
                response.effectiveUID == 0
            compatibilityHelperActive = verified && service.status != .enabled
            refreshStatus()
            if verified { lastError = nil }
            return verified
        } catch {
            compatibilityHelperActive = false
            lastError = error.localizedDescription
            refreshStatus()
            return false
        }
    }
}
