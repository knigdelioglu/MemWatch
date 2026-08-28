import Darwin
import Dispatch
import Foundation
import Security

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
            let response = try engine.scan(ruleIDs: request.ruleIDs)
            reply(try JSONEncoder().encode(response))
        } catch {
            let response = PrivilegedScanResponse(items: [], issues: [error.localizedDescription])
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
        guard let code = guestCode(for: connection) else { return false }

        var requirement: SecRequirement?
        let requirementString = "identifier \"\(MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier)\""
        guard SecRequirementCreateWithString(
            requirementString as CFString,
            [],
            &requirement
        ) == errSecSuccess,
        let requirement,
        SecCodeCheckValidity(code, [], requirement) == errSecSuccess else {
            return false
        }

        guard let clientInfo = signingInformation(for: code) else { return false }
        let clientIdentifier = clientInfo[kSecCodeInfoIdentifier as String] as? String
        guard clientIdentifier == MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier else {
            return false
        }

        if let helperCode = selfCode(),
           let helperInfo = signingInformation(for: helperCode),
           let helperTeam = helperInfo[kSecCodeInfoTeamIdentifier as String] as? String,
           !helperTeam.isEmpty {
            let clientTeam = clientInfo[kSecCodeInfoTeamIdentifier as String] as? String
            guard clientTeam == helperTeam else { return false }
        } else {
            // Local/ad-hoc builds have no Team ID. Keep a second invariant in addition
            // to the code identifier so a bare PID race is not sufficient.
            guard let executableURL = codePath(code) else { return false }
            let suffix = "/MemWatch.app/Contents/MacOS/MemWatch"
            guard executableURL.path.hasSuffix(suffix) else { return false }
        }

        return true
    }

    private func guestCode(for connection: NSXPCConnection) -> SecCode? {
        if let auditData = auditTokenData(from: connection) {
            var code: SecCode?
            let attributes = [kSecGuestAttributeAudit as String: auditData] as CFDictionary
            if SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
               let code {
                return code
            }
        }

        // Fallback only when the private auditToken accessor is unavailable.
        // Signing requirement and executable-path checks still apply.
        var code: SecCode?
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
        ] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else {
            return nil
        }
        return code
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

    private func codePath(_ code: SecCode) -> URL? {
        var url: CFURL?
        guard SecCodeCopyPath(code, [], &url) == errSecSuccess, let url else { return nil }
        return url as URL
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
        }
    }
}

private struct PrivilegedRulePolicy {
    let roots: [String]
    let minimumAge: TimeInterval?
    let requiresMissingLaunchExecutable: Bool
    let blockAppleNamedItems: Bool
    let privateVarCacheOnly: Bool
}

private final class PrivilegedOperationEngine {
    private let fileManager = FileManager.default

    private let removalPolicies: [String: PrivilegedRulePolicy] = [
        "system.cache": PrivilegedRulePolicy(
            roots: ["/Library/Caches"],
            minimumAge: nil,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: true,
            privateVarCacheOnly: false
        ),
        "system.log.old": PrivilegedRulePolicy(
            roots: ["/Library/Logs"],
            minimumAge: 30 * 24 * 60 * 60,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: false,
            privateVarCacheOnly: false
        ),
        "diagnostic.system.old": PrivilegedRulePolicy(
            roots: ["/Library/Logs/DiagnosticReports"],
            minimumAge: 30 * 24 * 60 * 60,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: false,
            privateVarCacheOnly: false
        ),
        "application.leftover.system": PrivilegedRulePolicy(
            roots: ["/Library/Application Support", "/Library/Caches", "/Library/Preferences"],
            minimumAge: nil,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: true,
            privateVarCacheOnly: false
        ),
        "launchitem.orphan.system": PrivilegedRulePolicy(
            roots: ["/Library/LaunchAgents", "/Library/LaunchDaemons"],
            minimumAge: nil,
            requiresMissingLaunchExecutable: true,
            blockAppleNamedItems: true,
            privateVarCacheOnly: false
        ),
        "privatevar.temp.old": PrivilegedRulePolicy(
            roots: ["/private/var/tmp", "/private/var/folders"],
            minimumAge: 7 * 24 * 60 * 60,
            requiresMissingLaunchExecutable: false,
            blockAppleNamedItems: false,
            privateVarCacheOnly: true
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

    func scan(ruleIDs: [String]) throws -> PrivilegedScanResponse {
        var items: [PrivilegedScannedItem] = []
        var issues: [String] = []

        for ruleID in Set(ruleIDs) {
            do {
                switch ruleID {
                case "system.cache":
                    items.append(contentsOf: scanImmediateChildren(
                        root: "/Library/Caches",
                        ruleID: ruleID,
                        minimumAge: nil,
                        skipAppleNamedItems: true,
                        reason: "Third-party system-wide cache"
                    ))
                case "system.log.old":
                    items.append(contentsOf: scanImmediateChildren(
                        root: "/Library/Logs",
                        ruleID: ruleID,
                        minimumAge: 30 * 24 * 60 * 60,
                        skipAppleNamedItems: false,
                        reason: "Old system-wide log"
                    ).filter { $0.displayName != "DiagnosticReports" })
                case "diagnostic.system.old":
                    items.append(contentsOf: scanImmediateChildren(
                        root: "/Library/Logs/DiagnosticReports",
                        ruleID: ruleID,
                        minimumAge: 30 * 24 * 60 * 60,
                        skipAppleNamedItems: false,
                        reason: "Old system diagnostic report"
                    ))
                case "launchitem.orphan.system":
                    items.append(contentsOf: scanOrphanLaunchItems())
                case "privatevar.temp.old":
                    items.append(contentsOf: scanPrivateTemporaryData())
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

        return PrivilegedScanResponse(items: items, issues: issues)
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
            let latest = latestModificationDate(at: path) ?? Date()
            guard Date().timeIntervalSince(latest) >= minimumAge else {
                throw PrivilegedHelperFailure.targetTooNew
            }
        }

        let before = allocatedSize(at: path)
        try fileManager.removeItem(atPath: path)
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
    ) -> [PrivilegedScannedItem] {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .contentAccessDateKey],
            options: []
        ) else {
            return []
        }

        return children.compactMap { url in
            if skipAppleNamedItems && isAppleNamed(url.lastPathComponent) {
                return nil
            }
            if let minimumAge {
                let timestamp = latestModificationDate(at: url.path) ?? Date()
                guard Date().timeIntervalSince(timestamp) >= minimumAge else { return nil }
            }
            return scannedItem(url: url, ruleID: ruleID, reason: reason)
        }
    }

    private func scanOrphanLaunchItems() -> [PrivilegedScannedItem] {
        var results: [PrivilegedScannedItem] = []
        for root in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for url in files where url.pathExtension.lowercased() == "plist" {
                if isAppleNamed(url.deletingPathExtension().lastPathComponent) { continue }
                guard launchItemPointsToMissingExecutable(url.path) else { continue }
                if let item = scannedItem(
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

    private func scanPrivateTemporaryData() -> [PrivilegedScannedItem] {
        var results: [PrivilegedScannedItem] = []

        results.append(contentsOf: scanImmediateChildren(
            root: "/private/var/tmp",
            ruleID: "privatevar.temp.old",
            minimumAge: 7 * 24 * 60 * 60,
            skipAppleNamedItems: false,
            reason: "Old temporary data"
        ))

        let foldersRoot = URL(fileURLWithPath: "/private/var/folders", isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        if let enumerator = fileManager.enumerator(
            at: foldersRoot,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let url as URL in enumerator {
                let relativeDepth = url.pathComponents.count - foldersRoot.pathComponents.count
                if relativeDepth > 4 {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    continue
                }
                guard url.lastPathComponent == "T" || url.lastPathComponent == "C" else {
                    continue
                }

                if let children = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    for child in children {
                        let timestamp = latestModificationDate(at: child.path) ?? Date()
                        guard Date().timeIntervalSince(timestamp) >= 7 * 24 * 60 * 60 else { continue }
                        if let item = scannedItem(
                            url: child,
                            ruleID: "privatevar.temp.old",
                            reason: "Old per-user cache/temporary data under /private/var/folders"
                        ) {
                            results.append(item)
                        }
                    }
                }
                enumerator.skipDescendants()
            }
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
        if isAppleNamed(name) {
            throw PrivilegedHelperFailure.protectedTarget(
                "Apple-owned identifiers are not removable by MemWatch."
            )
        }
    }

    private func isAppleNamed(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("com.apple.") ||
            lower.hasPrefix("group.com.apple.") ||
            lower == "apple" ||
            lower.hasPrefix("apple.")
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
            mode: UInt32(info.st_mode)
        )
    }

    // MARK: Metadata

    private func scannedItem(
        url: URL,
        ruleID: String,
        reason: String
    ) -> PrivilegedScannedItem? {
        guard let fileIdentity = try? identity(at: url.path) else { return nil }
        guard (fileIdentity.mode & UInt32(S_IFMT)) != UInt32(S_IFLNK) else { return nil }

        let values = try? url.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey
        ])
        let size = sizes(at: url.path)

        return PrivilegedScannedItem(
            ruleID: ruleID,
            path: url.path,
            maintenanceIdentifier: nil,
            displayName: url.lastPathComponent,
            logicalBytes: size.logical,
            allocatedBytes: size.allocated,
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            lastAccessedAt: values?.contentAccessDate,
            identity: fileIdentity,
            reason: reason
        )
    }

    private func allocatedSize(at path: String) -> UInt64 {
        sizes(at: path).allocated
    }

    private func sizes(at path: String) -> (logical: UInt64, allocated: UInt64) {
        let root = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ]

        guard let values = try? root.resourceValues(forKeys: keys) else { return (0, 0) }
        if values.isSymbolicLink == true { return (0, 0) }
        if values.isDirectory != true {
            let logical = UInt64(max(values.fileSize ?? 0, 0))
            let rawAllocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            return (logical, UInt64(max(rawAllocated, 0)))
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return (0, 0) }

        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        for case let url as URL in enumerator {
            guard let child = try? url.resourceValues(forKeys: keys) else { continue }
            if child.isSymbolicLink == true {
                if child.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard child.isRegularFile == true else { continue }
            logical = adding(logical, UInt64(max(child.fileSize ?? 0, 0)))
            let rawAllocated = child.totalFileAllocatedSize ?? child.fileAllocatedSize ?? child.fileSize ?? 0
            allocated = adding(allocated, UInt64(max(rawAllocated, 0)))
        }
        return (logical, allocated)
    }

    private func latestModificationDate(at path: String) -> Date? {
        let root = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey
        ]
        guard let rootValues = try? root.resourceValues(forKeys: keys) else { return nil }

        var latest = rootValues.contentModificationDate
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            return latest
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return latest }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if let date = values.contentModificationDate,
               latest == nil || date > latest! {
                latest = date
            }
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
