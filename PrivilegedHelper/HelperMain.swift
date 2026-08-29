import Darwin
import Dispatch
import Foundation
import Security

private extension CleanupSecureNodeIdentity {
    init(_ identity: PrivilegedFileIdentity) {
        self.init(
            deviceID: identity.deviceID,
            inode: identity.inode,
            ownerUID: identity.ownerUID,
            mode: identity.mode,
            sizeBytes: identity.sizeBytes,
            modificationTimeNanoseconds: identity.modificationTimeNanoseconds
        )
    }
}

@main
struct MemWatchPrivilegedHelperMain {
    static func main() {
        guard geteuid() == 0 else {
            fputs("MemWatchPrivilegedHelper must run as root via launchd.\n", stderr)
            exit(EXIT_FAILURE)
        }

        let listener = NSXPCListener(
            machServiceName: MemWatchPrivilegedHelperConstants.machServiceName
        )
        let delegate = PrivilegedHelperListenerDelegate()
        listener.delegate = delegate
        listener.resume()
        dispatchMain()
    }
}

private final class PrivilegedHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let validator = PrivilegedClientValidator()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard validator.isAuthorized(newConnection) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(
            with: MemWatchPrivilegedHelperXPC.self
        )
        newConnection.exportedObject = PrivilegedHelperService()
        newConnection.resume()
        return true
    }
}

private final class PrivilegedHelperService: NSObject, MemWatchPrivilegedHelperXPC {
    private let engine = PrivilegedOperationEngine()

    func ping(withReply reply: @escaping (Data) -> Void) {
        let response = PrivilegedPingResponse(
            protocolVersion: MemWatchPrivilegedHelperConstants.protocolVersion,
            helperPID: getpid(),
            effectiveUID: geteuid()
        )
        reply((try? JSONEncoder().encode(response)) ?? Data())
    }

    func scan(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        do {
            let request = try JSONDecoder().decode(PrivilegedScanRequest.self, from: requestData)
            guard request.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion else {
                throw PrivilegedHelperFailure.protocolMismatch
            }
            let response = try engine.scan(requestID: request.requestID, ruleIDs: request.ruleIDs)
            reply(try JSONEncoder().encode(response))
        } catch {
            let requestID = (try? JSONDecoder().decode(PrivilegedScanRequest.self, from: requestData).requestID) ?? UUID()
            let response = PrivilegedScanResponse(requestID: requestID, items: [], issues: [error.localizedDescription])
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }

    func execute(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let decoder = JSONDecoder()
        do {
            let request = try decoder.decode(PrivilegedOperationRequest.self, from: requestData)
            guard request.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion else {
                throw PrivilegedHelperFailure.protocolMismatch
            }
            let response = try engine.execute(request)
            reply(try JSONEncoder().encode(response))
        } catch {
            let requestID = (try? decoder.decode(PrivilegedOperationRequest.self, from: requestData).requestID) ?? UUID()
            let response = PrivilegedOperationResponse(
                requestID: requestID,
                success: false,
                message: error.localizedDescription
            )
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }
}

// MARK: - XPC caller verification

private struct PrivilegedClientValidator {
    func isAuthorized(_ connection: NSXPCConnection) -> Bool {
        guestCodes(for: connection).contains { isAuthorized($0) }
    }

    private func isAuthorized(_ code: SecCode) -> Bool {

        guard let helperCode = selfCode(),
              let helperInfo = signingInformation(for: helperCode),
              let helperIdentifier = helperInfo[kSecCodeInfoIdentifier as String] as? String,
              MemWatchPrivilegedHelperConstants.isExpectedHelperCodeIdentifier(helperIdentifier),
              let clientInfo = signingInformation(for: code),
              clientInfo[kSecCodeInfoIdentifier as String] as? String == MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier else {
            return false
        }

        let helperTeam = teamIdentifier(in: helperInfo)
        if let helperTeam, !helperTeam.isEmpty {
            return isTeamAuthorized(
                code: code,
                clientInfo: clientInfo,
                helperTeam: helperTeam
            )
        }

        // Ad-hoc signatures do not contain a Team ID. They are supported for
        // local/private builds only through an administrator-installed,
        // root-owned manifest that pins the exact client executable and its
        // live code hash. A bundle identifier or a path by itself is not
        // sufficient for a root XPC service.
        return isAdHocAuthorized(code: code, clientInfo: clientInfo)
    }

    private func isTeamAuthorized(
        code: SecCode,
        clientInfo: [String: Any],
        helperTeam: String
    ) -> Bool {
        var requirement: SecRequirement?
        let requirementString = "identifier \"\(MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(helperTeam)\""
        guard SecRequirementCreateWithString(
            requirementString as CFString,
            [],
            &requirement
        ) == errSecSuccess,
        let requirement,
        SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            return false
        }

        let clientTeam = teamIdentifier(in: clientInfo)
        guard clientTeam == helperTeam else { return false }

        return true
    }

    private func isAdHocAuthorized(
        code: SecCode,
        clientInfo: [String: Any]
    ) -> Bool {
        guard teamIdentifier(in: clientInfo) == nil,
              isValidMainAppIdentifier(code),
              let executableURL = clientInfo[kSecCodeInfoMainExecutable as String] as? URL,
              let manifest = loadAuthorizationManifest(),
              manifest.bundleIdentifier == MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier,
              canonicalPath(executableURL.path) == canonicalPath(manifest.executablePath),
              !manifest.codeHashes.isEmpty else {
            return false
        }

        let expectedHashes = Set(manifest.codeHashes.map { $0.lowercased() })
        let clientHashes = codeHashes(in: clientInfo)
        return !expectedHashes.isDisjoint(with: clientHashes)
    }

    private func isValidMainAppIdentifier(_ code: SecCode) -> Bool {
        var requirement: SecRequirement?
        let requirementString = "identifier \"\(MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier)\""
        guard SecRequirementCreateWithString(
            requirementString as CFString,
            [],
            &requirement
        ) == errSecSuccess,
        let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func teamIdentifier(in information: [String: Any]) -> String? {
        guard let value = information[kSecCodeInfoTeamIdentifier as String] as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func codeHashes(in information: [String: Any]) -> Set<String> {
        guard let values = information[kSecCodeInfoCdHashes as String] as? [Any] else {
            return []
        }
        return Set(values.compactMap { value in
            guard let data = value as? Data else { return nil }
            return data.map { String(format: "%02x", $0) }.joined()
        })
    }

    private func loadAuthorizationManifest() -> PrivilegedHelperAuthorizationManifest? {
        let url = URL(fileURLWithPath: MemWatchPrivilegedHelperConstants.authorizationManifestPath)
        guard isSecureManifestFile(at: url),
              let data = try? Data(contentsOf: url),
              let manifest = try? PropertyListDecoder().decode(
                PrivilegedHelperAuthorizationManifest.self,
                from: data
              ),
              manifest.version == PrivilegedHelperAuthorizationManifest.currentVersion,
              manifest.executablePath.hasPrefix("/"),
              manifest.executablePath.count <= 4_096,
              manifest.codeHashes.count <= 8,
              manifest.codeHashes.allSatisfy(isValidHash) else {
            return nil
        }
        return manifest
    }

    private func isValidHash(_ hash: String) -> Bool {
        hash.count == 40 && hash.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70, 97...102:
                return true
            default:
                return false
            }
        }
    }

    private func isSecureManifestFile(at url: URL) -> Bool {
        var fileInfo = stat()
        guard lstat(url.path, &fileInfo) == 0,
              (UInt32(fileInfo.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFREG),
              fileInfo.st_uid == 0,
              (UInt32(fileInfo.st_mode) & 0o022) == 0 else {
            return false
        }

        var directoryInfo = stat()
        let directory = url.deletingLastPathComponent().path
        guard lstat(directory, &directoryInfo) == 0,
              (UInt32(directoryInfo.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFDIR),
              directoryInfo.st_uid == 0,
              (UInt32(directoryInfo.st_mode) & 0o022) == 0 else {
            return false
        }
        return true
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func guestCodes(for connection: NSXPCConnection) -> [SecCode] {
        var candidates: [SecCode] = []

        if let auditData = auditTokenData(from: connection) {
            var code: SecCode?
            let attributes = [kSecGuestAttributeAudit as String: auditData] as CFDictionary
            if SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
               let code {
                candidates.append(code)
            }
        }

        // On recent macOS releases the private NSXPCConnection auditToken
        // accessor can yield a code object that is not the peer process. Keep
        // the PID-derived candidate as an independent fallback; the complete
        // signing, path, and root manifest checks still apply to every
        // candidate before a connection is accepted.
        var code: SecCode?
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
        ] as CFDictionary
        if SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
           let code {
            candidates.append(code)
        }
        return candidates
    }

    private func auditTokenData(from connection: NSXPCConnection) -> Data? {
        let selector = NSSelectorFromString("auditToken")
        guard connection.responds(to: selector) else { return nil }

        if let data = connection.value(forKey: "auditToken") as? Data {
            return data
        }

        guard let value = connection.value(forKey: "auditToken") as? NSValue else {
            return nil
        }

        var token = audit_token_t()
        value.getValue(&token)
        return withUnsafeBytes(of: &token) { Data($0) }
    }

    private func signingInformation(for code: SecCode) -> [String: Any]? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess else {
            return nil
        }
        return information as? [String: Any]
    }

    private func selfCode() -> SecCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess else { return nil }
        return code
    }

}

// MARK: - Typed privileged operations

private enum PrivilegedHelperFailure: LocalizedError {
    case protocolMismatch
    case unsupportedRule(String)
    case malformedRequest(String)
    case rejectedPath(String)
    case identityMismatch
    case targetTooNew
    case protectedTarget(String)
    case commandFailed(String)
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .protocolMismatch:
            return "Privileged helper protocol version mismatch."
        case .unsupportedRule(let rule):
            return "Privileged rule is not allowed: \(rule)"
        case .malformedRequest(let message):
            return "Malformed privileged request: \(message)"
        case .rejectedPath(let path):
            return "Privileged cleanup path was rejected: \(path)"
        case .identityMismatch:
            return "Cleanup target changed after scanning; operation was cancelled."
        case .targetTooNew:
            return "Cleanup target is newer than the privileged rule allows."
        case .protectedTarget(let message):
            return "Protected target: \(message)"
        case .commandFailed(let message):
            return message
        case .scanFailed(let message):
            return "Privileged cleanup scan failed: \(message)"
        }
    }
}

private struct PrivilegedRulePolicy {
    let roots: [String]
    let minimumAge: TimeInterval?
    let requiresMissingLaunchExecutable: Bool
    let blockAppleNamedItems: Bool
    let privateVarCacheOnly: Bool
    let requiresDirectChild: Bool
    let requiresBundleIdentifier: Bool
    let rejectsDiagnosticReportsDirectory: Bool
}

private final class PrivilegedOperationEngine {
    private let fileManager = FileManager.default

    private let removalPolicies: [String: PrivilegedRulePolicy] = [
        "system.cache": PrivilegedRulePolicy(
            roots: ["/Library/Caches"],
            minimumAge: nil,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: true,
            privateVarCacheOnly: false,
            requiresDirectChild: true,
            requiresBundleIdentifier: false,
            rejectsDiagnosticReportsDirectory: false
        ),
        "system.log.old": PrivilegedRulePolicy(
            roots: ["/Library/Logs"],
            minimumAge: 30 * 24 * 60 * 60,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: false,
            privateVarCacheOnly: false,
            requiresDirectChild: true,
            requiresBundleIdentifier: false,
            rejectsDiagnosticReportsDirectory: true
        ),
        "diagnostic.system.old": PrivilegedRulePolicy(
            roots: ["/Library/Logs/DiagnosticReports"],
            minimumAge: 30 * 24 * 60 * 60,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: false,
            privateVarCacheOnly: false,
            requiresDirectChild: true,
            requiresBundleIdentifier: false,
            rejectsDiagnosticReportsDirectory: false
        ),
        "application.leftover.system": PrivilegedRulePolicy(
            roots: ["/Library/Application Support", "/Library/Caches", "/Library/Preferences"],
            minimumAge: nil,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: true,
            privateVarCacheOnly: false,
            requiresDirectChild: true,
            requiresBundleIdentifier: true,
            rejectsDiagnosticReportsDirectory: false
        ),
        "launchitem.orphan.system": PrivilegedRulePolicy(
            roots: ["/Library/LaunchAgents", "/Library/LaunchDaemons"],
            minimumAge: nil,
            requiresMissingLaunchExecutable: true,
            blockAppleNamedItems: true,
            privateVarCacheOnly: false,
            requiresDirectChild: true,
            requiresBundleIdentifier: false,
            rejectsDiagnosticReportsDirectory: false
        ),
        "privatevar.temp.old": PrivilegedRulePolicy(
            roots: ["/private/var/tmp", "/private/var/folders"],
            minimumAge: 7 * 24 * 60 * 60,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: false,
            privateVarCacheOnly: true,
            requiresDirectChild: false,
            requiresBundleIdentifier: false,
            rejectsDiagnosticReportsDirectory: false
        )
    ]

    func execute(_ request: PrivilegedOperationRequest) throws -> PrivilegedOperationResponse {
        switch request.operation {
        case .removeApprovedPath:
            return try removeApprovedPath(request)
        case .thinTimeMachineSnapshots:
            return try thinTimeMachineSnapshots(request)
        }
    }

    func scan(requestID: UUID, ruleIDs: [String]) throws -> PrivilegedScanResponse {
        var items: [PrivilegedScannedItem] = []
        var issues: [String] = []

        for ruleID in Set(ruleIDs).sorted() {
            do {
                switch ruleID {
                case "system.cache":
                    items.append(contentsOf: try scanImmediateChildren(
                        root: "/Library/Caches",
                        ruleID: ruleID,
                        minimumAge: nil,
                        skipAppleNamedItems: true,
                        reason: "Third-party system-wide cache"
                    ))
                case "system.log.old":
                    items.append(contentsOf: try scanImmediateChildren(
                        root: "/Library/Logs",
                        ruleID: ruleID,
                        minimumAge: 30 * 24 * 60 * 60,
                        skipAppleNamedItems: false,
                        reason: "Old system-wide log"
                    ).filter { $0.displayName != "DiagnosticReports" })
                case "diagnostic.system.old":
                    items.append(contentsOf: try scanImmediateChildren(
                        root: "/Library/Logs/DiagnosticReports",
                        ruleID: ruleID,
                        minimumAge: 30 * 24 * 60 * 60,
                        skipAppleNamedItems: false,
                        reason: "Old system diagnostic report"
                    ))
                case "launchitem.orphan.system":
                    items.append(contentsOf: try scanOrphanLaunchItems())
                case "privatevar.temp.old":
                    items.append(contentsOf: try scanPrivateTemporaryData())
                case "timemachine.snapshot":
                    items.append(contentsOf: try scanTimeMachineSnapshots())
                case "application.leftover.system":
                    // Attribution is performed by the main app against its installed-app index.
                    continue
                default:
                    throw PrivilegedHelperFailure.unsupportedRule(ruleID)
                }
            } catch {
                issues.append("\(ruleID): \(error.localizedDescription)")
            }
        }

        return PrivilegedScanResponse(requestID: requestID, items: items, issues: issues)
    }

    private func removeApprovedPath(
        _ request: PrivilegedOperationRequest
    ) throws -> PrivilegedOperationResponse {
        guard let policy = removalPolicies[request.ruleID] else {
            throw PrivilegedHelperFailure.unsupportedRule(request.ruleID)
        }
        guard let rawPath = request.path, let expectedIdentity = request.expectedIdentity else {
            throw PrivilegedHelperFailure.malformedRequest("path and file identity are required")
        }

        let path = try validatedPath(rawPath, policy: policy)
        let currentIdentity = try identity(at: path)
        guard currentIdentity == expectedIdentity else {
            throw PrivilegedHelperFailure.identityMismatch
        }
        guard (currentIdentity.mode & UInt32(S_IFMT)) != UInt32(S_IFLNK) else {
            throw PrivilegedHelperFailure.rejectedPath(path)
        }

        if policy.requiresMissingLaunchExecutable {
            try validateOrphanLaunchItem(at: path)
        }
        if policy.blockAppleNamedItems {
            try rejectAppleNamedItem(at: path)
        }
        if let minimumAge = policy.minimumAge {
            let latest = try latestModificationDate(at: path) ?? Date()
            guard Date().timeIntervalSince(latest) >= minimumAge else {
                throw PrivilegedHelperFailure.targetTooNew
            }
        }

        let before = try allocatedSize(at: path)
        try CleanupSecureFileOperations.remove(
            atPath: path,
            expectedIdentity: CleanupSecureNodeIdentity(currentIdentity)
        )
        let reclaimed = fileManager.fileExists(atPath: path) ? 0 : before

        return PrivilegedOperationResponse(
            requestID: request.requestID,
            success: true,
            message: "Privileged cleanup completed.",
            reclaimedBytes: reclaimed
        )
    }

    private func thinTimeMachineSnapshots(
        _ request: PrivilegedOperationRequest
    ) throws -> PrivilegedOperationResponse {
        guard request.ruleID == "timemachine.snapshot" else {
            throw PrivilegedHelperFailure.unsupportedRule(request.ruleID)
        }
        guard let targetBytes = request.targetBytes, targetBytes > 0 else {
            throw PrivilegedHelperFailure.malformedRequest("targetBytes must be greater than zero")
        }

        let maximum: UInt64 = 500 * 1_024 * 1_024 * 1_024
        let bounded = min(targetBytes, maximum)
        let output = try runSystemTool(
            executable: "/usr/bin/tmutil",
            arguments: ["thinlocalsnapshots", "/", String(bounded), "4"]
        )

        return PrivilegedOperationResponse(
            requestID: request.requestID,
            success: true,
            message: "Time Machine local snapshot thinning completed.",
            commandOutput: output
        )
    }

    // MARK: Scan implementations

    private func scanImmediateChildren(
        root: String,
        ruleID: String,
        minimumAge: TimeInterval?,
        skipAppleNamedItems: Bool,
        reason: String
    ) throws -> [PrivilegedScannedItem] {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        guard try directoryExistsOrMissing(at: rootURL) else {
            return []
        }
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .contentAccessDateKey],
                options: []
            )
        } catch {
            throw PrivilegedHelperFailure.scanFailed("\(root): \(error.localizedDescription)")
        }

        var results: [PrivilegedScannedItem] = []
        for url in children {
            if skipAppleNamedItems && isAppleNamed(url.lastPathComponent) {
                continue
            }
            if let minimumAge {
                let timestamp = try latestModificationDate(at: url.path) ?? Date()
                guard Date().timeIntervalSince(timestamp) >= minimumAge else { continue }
            }
            if let item = try scannedItem(url: url, ruleID: ruleID, reason: reason) {
                results.append(item)
            }
        }
        return results
    }

    private func scanOrphanLaunchItems() throws -> [PrivilegedScannedItem] {
        var results: [PrivilegedScannedItem] = []
        for root in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard try directoryExistsOrMissing(at: rootURL) else {
                continue
            }
            let files: [URL]
            do {
                files = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            } catch {
                throw PrivilegedHelperFailure.scanFailed("\(root): \(error.localizedDescription)")
            }
            for url in files where url.pathExtension.lowercased() == "plist" {
                if isAppleNamed(url.deletingPathExtension().lastPathComponent) || launchItemHasAppleLabel(url.path) { continue }
                guard launchItemPointsToMissingExecutable(url.path) else { continue }
                if let item = try scannedItem(
                    url: url,
                    ruleID: "launchitem.orphan.system",
                    reason: "Launch item points to an executable that no longer exists"
                ) {
                    results.append(item)
                }
            }
        }
        return results
    }

    private func scanPrivateTemporaryData() throws -> [PrivilegedScannedItem] {
        var results: [PrivilegedScannedItem] = []

        results.append(contentsOf: try scanImmediateChildren(
            root: "/private/var/tmp",
            ruleID: "privatevar.temp.old",
            minimumAge: 7 * 24 * 60 * 60,
            skipAppleNamedItems: false,
            reason: "Old temporary data"
        ))

        let foldersRoot = URL(fileURLWithPath: "/private/var/folders", isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard try directoryExistsOrMissing(at: foldersRoot) else {
            return results
        }
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: foldersRoot,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw PrivilegedHelperFailure.scanFailed(foldersRoot.path)
        }
        for case let url as URL in enumerator {
            let relativeDepth = url.pathComponents.count - foldersRoot.pathComponents.count
            if relativeDepth > 4 {
                enumerator.skipDescendants()
                continue
            }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                throw PrivilegedHelperFailure.scanFailed("\(url.path): \(error.localizedDescription)")
            }
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else {
                continue
            }
            guard url.lastPathComponent == "T" || url.lastPathComponent == "C" else {
                continue
            }

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            } catch {
                throw PrivilegedHelperFailure.scanFailed("\(url.path): \(error.localizedDescription)")
            }
            for child in children {
                let timestamp = try latestModificationDate(at: child.path) ?? Date()
                guard Date().timeIntervalSince(timestamp) >= 7 * 24 * 60 * 60 else { continue }
                if let item = try scannedItem(
                    url: child,
                    ruleID: "privatevar.temp.old",
                    reason: "Old per-user cache/temporary data under /private/var/folders"
                ) {
                    results.append(item)
                }
            }
            enumerator.skipDescendants()
        }
        if enumerationError != nil {
            throw PrivilegedHelperFailure.scanFailed(foldersRoot.path)
        }

        return results
    }

    private func scanTimeMachineSnapshots() throws -> [PrivilegedScannedItem] {
        let output = try runSystemTool(
            executable: "/usr/bin/tmutil",
            arguments: ["listlocalsnapshots", "/"]
        )
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("com.apple.TimeMachine.") }
            .map { line in
                let identifier = line
                    .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return PrivilegedScannedItem(
                    ruleID: "timemachine.snapshot",
                    path: nil,
                    maintenanceIdentifier: identifier,
                    displayName: "Time Machine snapshot \(identifier)",
                    logicalBytes: 0,
                    allocatedBytes: 0,
                    createdAt: nil,
                    modifiedAt: nil,
                    lastAccessedAt: nil,
                    identity: nil,
                    reason: "Local Time Machine snapshot; managed only through tmutil"
                )
            }
    }

    // MARK: Validation

    private func validatedPath(
        _ rawPath: String,
        policy: PrivilegedRulePolicy
    ) throws -> String {
        guard rawPath.hasPrefix("/") else {
            throw PrivilegedHelperFailure.rejectedPath(rawPath)
        }

        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        guard standardized != "/", standardized != "/Library", standardized != "/private" else {
            throw PrivilegedHelperFailure.rejectedPath(standardized)
        }

        let protectedRoots = [
            "/System", "/bin", "/sbin", "/usr", "/dev", "/private/etc",
            "/private/var/db", "/private/var/root", "/private/var/vm"
        ]
        guard !protectedRoots.contains(where: { isEqualOrDescendant(standardized, of: $0) }) else {
            throw PrivilegedHelperFailure.protectedTarget(standardized)
        }

        guard let matchedRoot = policy.roots.first(where: {
            standardized != normalized($0) && isEqualOrDescendant(standardized, of: $0)
        }) else {
            throw PrivilegedHelperFailure.rejectedPath(standardized)
        }

        if policy.requiresDirectChild,
           !isDirectChild(standardized, of: matchedRoot) {
            throw PrivilegedHelperFailure.rejectedPath(standardized)
        }
        if policy.requiresBundleIdentifier,
           !isBundleIdentifier(URL(fileURLWithPath: standardized).lastPathComponent) {
            throw PrivilegedHelperFailure.rejectedPath(standardized)
        }
        if policy.rejectsDiagnosticReportsDirectory,
           URL(fileURLWithPath: standardized).lastPathComponent == "DiagnosticReports" {
            throw PrivilegedHelperFailure.rejectedPath(standardized)
        }

        let resolved = URL(fileURLWithPath: standardized)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard resolved == standardized,
              isEqualOrDescendant(resolved, of: matchedRoot) else {
            throw PrivilegedHelperFailure.rejectedPath(standardized)
        }

        if policy.privateVarCacheOnly && isEqualOrDescendant(standardized, of: "/private/var/folders") {
            let components = standardized.split(separator: "/").map(String.init)
            guard let markerIndex = components.firstIndex(where: { $0 == "T" || $0 == "C" }),
                  markerIndex < components.count - 1 else {
                throw PrivilegedHelperFailure.rejectedPath(standardized)
            }
        }

        return standardized
    }

    private func validateOrphanLaunchItem(at path: String) throws {
        guard path.hasSuffix(".plist"), launchItemPointsToMissingExecutable(path) else {
            throw PrivilegedHelperFailure.protectedTarget(
                "Launch item is not a confirmed orphan."
            )
        }
    }

    private func launchItemPointsToMissingExecutable(_ path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = object as? [String: Any] else {
            return false
        }

        let program = (plist["Program"] as? String) ??
            (plist["ProgramArguments"] as? [String])?.first
        guard let program, program.hasPrefix("/") else { return false }
        return !fileManager.fileExists(atPath: program)
    }

    private func rejectAppleNamedItem(at path: String) throws {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if isAppleNamed(name) || launchItemHasAppleLabel(path) {
            throw PrivilegedHelperFailure.protectedTarget(
                "Apple-owned identifiers are not removable by MemWatch."
            )
        }
    }

    private func launchItemHasAppleLabel(_ path: String) -> Bool {
        guard path.hasSuffix(".plist"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = object as? [String: Any],
              let label = plist["Label"] as? String else {
            return false
        }
        return isAppleNamed(label)
    }

    private func isAppleNamed(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("com.apple.") ||
            lower.hasPrefix("group.com.apple.") ||
            lower == "apple" ||
            lower.hasPrefix("apple.")
    }

    private func isDirectChild(_ path: String, of root: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: normalized(path)).pathComponents
        let rootComponents = URL(fileURLWithPath: normalized(root)).pathComponents
        return pathComponents.count == rootComponents.count + 1 &&
            Array(pathComponents.dropLast()) == rootComponents
    }

    private func isBundleIdentifier(_ value: String) -> Bool {
        var identifier = value
        for suffix in [".savedState", ".plist"] where identifier.hasSuffix(suffix) {
            identifier.removeLast(suffix.count)
        }
        let components = identifier.split(separator: ".")
        return identifier.count >= 5 &&
            components.count >= 2 &&
            !isAppleNamed(identifier) &&
            components.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    private func identity(at path: String) throws -> PrivilegedFileIdentity {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw PrivilegedHelperFailure.rejectedPath(path)
        }
        return PrivilegedFileIdentity(
            deviceID: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            ownerUID: UInt32(info.st_uid),
            mode: UInt32(info.st_mode),
            sizeBytes: UInt64(max(0, info.st_size)),
            modificationTimeNanoseconds: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        )
    }

    private func directoryExistsOrMissing(at url: URL) throws -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return false }
            throw PrivilegedHelperFailure.scanFailed(url.path)
        }
        guard (UInt32(info.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFDIR) else {
            throw PrivilegedHelperFailure.scanFailed(url.path)
        }
        return true
    }

    // MARK: Metadata

    private func scannedItem(
        url: URL,
        ruleID: String,
        reason: String
    ) throws -> PrivilegedScannedItem? {
        guard let fileIdentity = try? identity(at: url.path) else { return nil }
        guard (fileIdentity.mode & UInt32(S_IFMT)) != UInt32(S_IFLNK) else { return nil }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey
            ])
        } catch {
            throw PrivilegedHelperFailure.scanFailed("\(url.path): \(error.localizedDescription)")
        }
        let size = try sizes(at: url.path)

        return PrivilegedScannedItem(
            ruleID: ruleID,
            path: url.path,
            maintenanceIdentifier: nil,
            displayName: url.lastPathComponent,
            logicalBytes: size.logical,
            allocatedBytes: size.allocated,
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            lastAccessedAt: values.contentAccessDate,
            identity: fileIdentity,
            reason: reason
        )
    }

    private func allocatedSize(at path: String) throws -> UInt64 {
        try sizes(at: path).allocated
    }

    private func sizes(at path: String) throws -> (logical: UInt64, allocated: UInt64) {
        let root = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ]

        let values: URLResourceValues
        do {
            values = try root.resourceValues(forKeys: keys)
        } catch {
            throw PrivilegedHelperFailure.scanFailed("\(path): \(error.localizedDescription)")
        }
        if values.isSymbolicLink == true { return (0, 0) }
        if values.isDirectory != true {
            let logical = UInt64(max(values.fileSize ?? 0, 0))
            let rawAllocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            return (logical, UInt64(max(rawAllocated, 0)))
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw PrivilegedHelperFailure.scanFailed(path)
        }

        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        for case let url as URL in enumerator {
            let child: URLResourceValues
            do {
                child = try url.resourceValues(forKeys: keys)
            } catch {
                throw PrivilegedHelperFailure.scanFailed("\(url.path): \(error.localizedDescription)")
            }
            if child.isSymbolicLink == true {
                if child.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard child.isRegularFile == true else { continue }
            logical = adding(logical, UInt64(max(child.fileSize ?? 0, 0)))
            let rawAllocated = child.totalFileAllocatedSize ?? child.fileAllocatedSize ?? child.fileSize ?? 0
            allocated = adding(allocated, UInt64(max(rawAllocated, 0)))
        }
        if enumerationError != nil {
            throw PrivilegedHelperFailure.scanFailed(path)
        }
        return (logical, allocated)
    }

    private func latestModificationDate(at path: String) throws -> Date? {
        let root = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey
        ]
        let rootValues: URLResourceValues
        do {
            rootValues = try root.resourceValues(forKeys: keys)
        } catch {
            throw PrivilegedHelperFailure.scanFailed("\(path): \(error.localizedDescription)")
        }

        var latest = rootValues.contentModificationDate
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            return latest
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw PrivilegedHelperFailure.scanFailed(path)
        }

        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                throw PrivilegedHelperFailure.scanFailed("\(url.path): \(error.localizedDescription)")
            }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if let date = values.contentModificationDate,
               latest == nil || date > latest! {
                latest = date
            }
        }
        if enumerationError != nil {
            throw PrivilegedHelperFailure.scanFailed(path)
        }
        return latest
    }

    private func runSystemTool(
        executable: String,
        arguments: [String]
    ) throws -> String {
        let allowed = ["/usr/bin/tmutil"]
        guard allowed.contains(executable) else {
            throw PrivilegedHelperFailure.commandFailed("System tool is not allow-listed.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdout
        process.standardError = stderrPipe

        try process.run()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: outputData, as: UTF8.self)
        let errorText = String(decoding: errorData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw PrivilegedHelperFailure.commandFailed(
                errorText.isEmpty ? "tmutil exited with status \(process.terminationStatus)." : errorText
            )
        }
        return output
    }

    private func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isEqualOrDescendant(_ candidate: String, of root: String) -> Bool {
        let candidate = normalized(candidate)
        let root = normalized(root)
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : value
    }
}
