import Foundation
import Security
import ServiceManagement

enum PrivilegedHelperRegistrationState: String, Sendable {
    case unavailable
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case installing
}

enum PrivilegedHelperClientError: LocalizedError {
    case unavailable
    case invalidResponse
    case remote(String)
    case protocolMismatch
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Privileged helper is unavailable."
        case .invalidResponse: return "Privileged helper returned an invalid response."
        case .remote(let message): return message
        case .protocolMismatch: return "Privileged helper protocol version does not match MemWatch."
        case .timedOut: return "Privileged helper did not respond within the safety deadline."
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
        let response: PrivilegedScanResponse = try await withConnection { proxy, finish in
            proxy.scan(data) { responseData in
                finish(Self.decode(PrivilegedScanResponse.self, from: responseData))
            }
        }
        guard response.requestID == request.requestID else {
            throw PrivilegedHelperClientError.invalidResponse
        }
        return response
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
        guard response.requestID == request.requestID else {
            throw PrivilegedHelperClientError.invalidResponse
        }
        guard response.success else {
            throw PrivilegedHelperClientError.remote(response.message)
        }
        return response
    }

    private func withConnection<T: Sendable>(
        _ body: @escaping (MemWatchPrivilegedHelperXPC, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let cancellationBox = PrivilegedXPCRequestCancellationBox()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(
                machServiceName: MemWatchPrivilegedHelperConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: MemWatchPrivilegedHelperXPC.self)

            let lock = NSLock()
            var completed = false
            var timeoutWorkItem: DispatchWorkItem?
            func finish(_ result: Result<T, Error>) {
                lock.lock()
                guard !completed else {
                    lock.unlock()
                    return
                }
                completed = true
                timeoutWorkItem?.cancel()
                lock.unlock()
                connection.invalidate()
                continuation.resume(with: result)
            }

            cancellationBox.set { finish(.failure(CancellationError())) }
            guard !cancellationBox.isCancelled else { return }

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

            timeoutWorkItem = DispatchWorkItem {
                finish(.failure(PrivilegedHelperClientError.timedOut))
            }
            if let timeoutWorkItem {
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + .seconds(30),
                    execute: timeoutWorkItem
                )
            }
            body(proxy, finish)
            }
        }, onCancel: {
            cancellationBox.cancel()
        })
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

private final class PrivilegedXPCRequestCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?
    private(set) var isCancelled = false

    func set(_ handler: @escaping () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            handler()
            return
        }
        self.handler = handler
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}

private enum PrivilegedHelperCompatibilityError: LocalizedError {
    case bundledHelperMissing
    case bundledDaemonPlistMissing
    case malformedBundledDaemonPlist
    case clientAuthorizationManifestUnavailable
    case launchServicesRepairFailed(String)
    case administratorAuthorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "MemWatch uygulama paketinde yetkili yardımcı bulunamadı."
        case .bundledDaemonPlistMissing:
            return "MemWatch uygulama paketinde LaunchDaemon tanımı bulunamadı."
        case .malformedBundledDaemonPlist:
            return "MemWatch LaunchDaemon tanımı geçersiz veya helper yoluyla eşleşmiyor."
        case .clientAuthorizationManifestUnavailable:
            return "Yerel imzalı paket için yetkili yardımcı kimliği oluşturulamadı."
        case .launchServicesRepairFailed(let message):
            return "LaunchServices uyumluluk onarımı başarısız: \(message)"
        case .administratorAuthorizationFailed(let message):
            return "Yönetici yetkili yardımcı kurulumu başarısız: \(message)"
        }
    }
}

/// A deliberately narrow fallback for machines where SMAppService cannot locate
/// the bundled LaunchDaemon. It can only repair MemWatch's LaunchServices entry
/// or install MemWatch's own helper, plist and root-owned client identity pin at
/// fixed locations. No arbitrary command/path interface is exposed to the rest
/// of the application.
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

    private var installedAuthorizationManifestPath: String {
        MemWatchPrivilegedHelperConstants.authorizationManifestPath
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

    /// `lsregister` is an Apple-supplied but undocumented LaunchServices tool.
    /// This is intentionally isolated behind the private compatibility switch.
    /// It only refreshes registration for MemWatch's own bundle.
    func repairLaunchServicesRegistration() throws {
        let candidates = [
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        ]
        guard let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw PrivilegedHelperCompatibilityError.launchServicesRepairFailed("lsregister bulunamadı")
        }

        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-f", Bundle.main.bundleURL.standardizedFileURL.path]
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "çıkış kodu \(process.terminationStatus)"
            throw PrivilegedHelperCompatibilityError.launchServicesRepairFailed(message)
        }
    }

    func install() throws {
        let resources = try bundledResources()
        let temporaryPlist = try makeStandaloneLaunchDaemonPlist()
        let temporaryAuthorizationManifest = try makeAuthorizationManifest()
        defer { try? fileManager.removeItem(at: temporaryPlist) }
        defer { try? fileManager.removeItem(at: temporaryAuthorizationManifest) }

        let command = [
            "/bin/mkdir -p /Library/PrivilegedHelperTools \(shellQuote(MemWatchPrivilegedHelperConstants.authorizationDirectoryPath))",
            "/bin/chmod 755 \(shellQuote(MemWatchPrivilegedHelperConstants.authorizationDirectoryPath))",
            "/usr/sbin/chown root:wheel \(shellQuote(MemWatchPrivilegedHelperConstants.authorizationDirectoryPath))",
            "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "/usr/bin/install -o root -g wheel -m 755 \(shellQuote(resources.helper.path)) \(shellQuote(installedHelperPath))",
            "/usr/bin/install -o root -g wheel -m 644 \(shellQuote(temporaryPlist.path)) \(shellQuote(installedPlistPath))",
            "/usr/bin/install -o root -g wheel -m 644 \(shellQuote(temporaryAuthorizationManifest.path)) \(shellQuote(installedAuthorizationManifestPath))",
            "/bin/launchctl bootstrap system \(shellQuote(installedPlistPath))",
            "/bin/launchctl enable system/\(label)"
        ].joined(separator: "; ")

        try runWithAdministratorPrivileges(command)
    }

    func uninstall() throws {
        let command = [
            "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "/bin/rm -f \(shellQuote(installedPlistPath))",
            "/bin/rm -f \(shellQuote(installedHelperPath))",
            "/bin/rm -f \(shellQuote(installedAuthorizationManifestPath))"
        ].joined(separator: "; ")
        try runWithAdministratorPrivileges(command)
    }

    private func makeAuthorizationManifest() throws -> URL {
        guard let executableURL = Bundle.main.executableURL else {
            throw PrivilegedHelperCompatibilityError.clientAuthorizationManifestUnavailable
        }

        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess,
              let code else {
            throw PrivilegedHelperCompatibilityError.clientAuthorizationManifestUnavailable
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let information,
        let dictionary = information as? [String: Any],
        let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String,
        identifier == MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier else {
            throw PrivilegedHelperCompatibilityError.clientAuthorizationManifestUnavailable
        }

        let codeHashes = (dictionary[kSecCodeInfoCdHashes as String] as? [Any] ?? [])
            .compactMap { value -> String? in
                guard let data = value as? Data else { return nil }
                return data.map { String(format: "%02x", $0) }.joined()
            }
        guard !codeHashes.isEmpty else {
            throw PrivilegedHelperCompatibilityError.clientAuthorizationManifestUnavailable
        }

        let manifest = PrivilegedHelperAuthorizationManifest(
            bundleIdentifier: identifier,
            executablePath: executableURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path,
            codeHashes: Array(Set(codeHashes)).sorted()
        )
        let data = try PropertyListEncoder().encode(manifest)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("memwatch-\(UUID().uuidString)-authorization.plist")
        try data.write(to: url, options: [.atomic])
        return url
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
            // A missing/corrupt policy must never enable a private privileged
            // backend implicitly. The app can explicitly persist an opt-in
            // value after the user enables it.
            return false
        }
        guard preferences.requestedRootPaths.allSatisfy(Self.isAbsolutePath),
              preferences.projectRootPaths.allSatisfy(Self.isAbsolutePath) else {
            return false
        }
        return preferences.privateBackendEnabled
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && path.hasPrefix("/")
    }
}

@MainActor
final class PrivilegedHelperService: ObservableObject {
    @Published private(set) var state: PrivilegedHelperRegistrationState = .unavailable
    @Published private(set) var lastError: String?
    @Published private(set) var compatibilityHelperActive = false
    @Published private(set) var connectionVerified = false
    @Published private(set) var isRegistering = false

    private let service = SMAppService.daemon(
        plistName: MemWatchPrivilegedHelperConstants.daemonPlistName
    )
    private let compatibilityInstaller = PrivilegedHelperCompatibilityInstaller()
    let client = PrivilegedHelperClient()

    private static var requiresPinnedAuthorization: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess,
              let code else {
            return true
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let information,
        let dictionary = information as? [String: Any] else {
            return true
        }

        guard let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String else {
            return true
        }
        return team.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        refreshStatus()
    }

    var isAvailableForCleanup: Bool {
        connectionVerified && (state == .enabled || compatibilityHelperActive)
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

    func register() async -> Bool {
        guard !isRegistering else { return false }

        isRegistering = true
        defer { isRegistering = false }
        lastError = nil
        connectionVerified = false
        compatibilityHelperActive = false

        // A compatibility-installed daemon is not visible to SMAppService after
        // relaunch. Reuse it if its real XPC endpoint is already alive instead of
        // asking the user for administrator credentials again.
        if await verifyConnection() {
            return true
        }
        lastError = nil

        do {
            _ = try compatibilityInstaller.bundledResources()
        } catch {
            lastError = error.localizedDescription
            state = .unavailable
            return false
        }

        // Ad-hoc builds have no stable Team ID. Install a root-owned code-hash
        // pin before accepting their XPC connection; bundle identifiers and
        // paths alone must never authorize a root helper.
        if Self.requiresPinnedAuthorization {
            // A previous ad-hoc build may have left an SMAppService submission
            // under the same label. Remove that submission before installing
            // the manifest-backed compatibility daemon.
            try? await service.unregister()
            state = .installing
            if let errorMessage = await Self.compatibilityInstallError() {
                compatibilityHelperActive = false
                lastError = errorMessage
                refreshStatus()
                return false
            }

            let verified = await verifyConnection()
            if verified {
                compatibilityHelperActive = true
                refreshStatus()
            }
            return verified
        }

        do {
            try service.register()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()

        if state == .enabled {
            return await verifyConnection()
        }

        if state == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return false
        }

        let compatibilityEnabled = PrivateCompatibilityPolicy.isEnabled
        if state == .notFound && compatibilityEnabled {
            if let errorMessage = await Self.compatibilityRepairError() {
                lastError = errorMessage
            } else {
                do {
                    try service.register()
                } catch {
                    lastError = error.localizedDescription
                }
                refreshStatus()
            }

            if state == .enabled {
                return await verifyConnection()
            }
            if state == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return false
            }
        }

        guard state == .notFound || state == .notRegistered || state == .unavailable else {
            return false
        }
        guard compatibilityEnabled else {
            if lastError == nil {
                lastError = "SMAppService yardımcıyı bulamadı. Özel uyumluluk yöntemleri kapalı olduğu için alternatif kurulum kullanılmadı."
            }
            return false
        }

        state = .installing
        if let errorMessage = await Self.compatibilityInstallError() {
            compatibilityHelperActive = false
            lastError = errorMessage
            refreshStatus()
            return false
        }

        // The installed daemon is authoritative only after its XPC endpoint
        // accepts a ping. This also covers a short launchd startup delay.
        return await verifyConnection()
    }

    nonisolated private static func compatibilityRepairError() async -> String? {
        await Task.detached(priority: .userInitiated) {
            do {
                try PrivilegedHelperCompatibilityInstaller().repairLaunchServicesRegistration()
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    nonisolated private static func compatibilityInstallError() async -> String? {
        await Task.detached(priority: .userInitiated) {
            do {
                try PrivilegedHelperCompatibilityInstaller().install()
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
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
        connectionVerified = false
        refreshStatus()
    }

    func verifyConnection() async -> Bool {
        for attempt in 0..<3 {
            do {
                let response = try await client.ping()
                guard response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion,
                      response.effectiveUID == 0 else {
                    throw PrivilegedHelperClientError.protocolMismatch
                }
                connectionVerified = true
                compatibilityHelperActive = service.status != .enabled
                refreshStatus()
                lastError = nil
                return true
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                connectionVerified = false
                compatibilityHelperActive = false
                lastError = error.localizedDescription
                refreshStatus()
                return false
            }
        }
        return false
    }
}
