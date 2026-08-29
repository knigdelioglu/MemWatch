import Foundation

@main
struct PrivilegedHelperProtocolTests {
    static func main() throws {
        let identity = PrivilegedFileIdentity(deviceID: 7, inode: 11, ownerUID: 501, mode: 0o100644)
        let request = PrivilegedOperationRequest(
            requestID: UUID(),
            operation: .removeApprovedPath,
            ruleID: "system.cache",
            path: "/Library/Caches/example",
            expectedIdentity: identity
        )

        let encodedRequest = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(PrivilegedOperationRequest.self, from: encodedRequest)
        precondition(decodedRequest.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion)
        precondition(decodedRequest.requestID == request.requestID)
        precondition(decodedRequest.operation == .removeApprovedPath)
        precondition(decodedRequest.ruleID == "system.cache")
        precondition(decodedRequest.path == "/Library/Caches/example")
        precondition(decodedRequest.expectedIdentity == identity)

        let scan = PrivilegedScanRequest(ruleIDs: ["system.cache", "timemachine.snapshot"])
        let encodedScan = try JSONEncoder().encode(scan)
        let decodedScan = try JSONDecoder().decode(PrivilegedScanRequest.self, from: encodedScan)
        precondition(decodedScan.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion)
        precondition(decodedScan.requestID == scan.requestID)
        precondition(decodedScan.ruleIDs == ["system.cache", "timemachine.snapshot"])

        let authorizationManifest = PrivilegedHelperAuthorizationManifest(
            bundleIdentifier: MemWatchPrivilegedHelperConstants.mainAppBundleIdentifier,
            executablePath: "/Applications/MemWatch.app/Contents/MacOS/MemWatch",
            codeHashes: ["0123456789abcdef0123456789abcdef01234567"]
        )
        let encodedManifest = try PropertyListEncoder().encode(authorizationManifest)
        let decodedManifest = try PropertyListDecoder().decode(
            PrivilegedHelperAuthorizationManifest.self,
            from: encodedManifest
        )
        precondition(decodedManifest == authorizationManifest)
        precondition(authorizationManifest.version == PrivilegedHelperAuthorizationManifest.currentVersion)

        precondition(
            MemWatchPrivilegedHelperConstants.isExpectedHelperCodeIdentifier(
                MemWatchPrivilegedHelperConstants.helperCodeIdentifier
            )
        )
        precondition(
            MemWatchPrivilegedHelperConstants.isExpectedHelperCodeIdentifier(
                "MemWatchPrivilegedHelper-0123456789abcdef0123456789abcdef01234567"
            )
        )
        precondition(
            !MemWatchPrivilegedHelperConstants.isExpectedHelperCodeIdentifier(
                "MemWatchPrivilegedHelper-not-a-code-hash"
            )
        )

        let response = PrivilegedOperationResponse(
            requestID: request.requestID,
            success: true,
            message: "ok",
            reclaimedBytes: 4096,
            commandOutput: nil
        )
        let encodedResponse = try JSONEncoder().encode(response)
        let decodedResponse = try JSONDecoder().decode(PrivilegedOperationResponse.self, from: encodedResponse)
        precondition(decodedResponse.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion)
        precondition(decodedResponse.success)
        precondition(decodedResponse.requestID == request.requestID)
        precondition(decodedResponse.reclaimedBytes == 4096)

        print("PASS Privileged helper protocol")
    }
}
