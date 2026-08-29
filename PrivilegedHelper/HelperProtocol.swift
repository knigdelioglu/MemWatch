import Foundation
import Security

// Xcode 26's Security overlay requires SecStaticCode for signing-information
// and path queries. The helper validates a live XPC guest as SecCode first,
// then converts that guest to its static code before calling those APIs.
// Keeping these overloads next to the shared helper protocol avoids unsafe
// forced casts and preserves the audit-token based validation flow.
@inline(__always)
func SecCodeCopySigningInformation(
    _ code: SecCode,
    _ flags: SecCSFlags,
    _ information: UnsafeMutablePointer<CFDictionary?>
) -> OSStatus {
    var staticCode: SecStaticCode?
    let conversionStatus = Security.SecCodeCopyStaticCode(code, [], &staticCode)
    guard conversionStatus == errSecSuccess, let staticCode else {
        return conversionStatus
    }
    return Security.SecCodeCopySigningInformation(staticCode, flags, information)
}

enum MemWatchPrivilegedHelperConstants {
    static let daemonPlistName = "com.knigdelioglu.MemWatch.PrivilegedHelper.plist"
    static let daemonLabel = "com.knigdelioglu.MemWatch.PrivilegedHelper"
    static let machServiceName = "com.knigdelioglu.MemWatch.PrivilegedHelper"
    static let mainAppBundleIdentifier = "com.knigdelioglu.MemWatch"
    static let protocolVersion = 2
}

enum PrivilegedOperationKind: String, Codable, Sendable {
    case removeApprovedPath
    case thinTimeMachineSnapshots
}

struct PrivilegedFileIdentity: Codable, Equatable, Sendable {
    let deviceID: UInt64
    let inode: UInt64
    let ownerUID: UInt32
    let mode: UInt32
    let sizeBytes: UInt64?
    let modificationTimeNanoseconds: Int64?

    init(
        deviceID: UInt64,
        inode: UInt64,
        ownerUID: UInt32,
        mode: UInt32,
        sizeBytes: UInt64? = nil,
        modificationTimeNanoseconds: Int64? = nil
    ) {
        self.deviceID = deviceID
        self.inode = inode
        self.ownerUID = ownerUID
        self.mode = mode
        self.sizeBytes = sizeBytes
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
    }
}

struct PrivilegedOperationRequest: Codable, Sendable {
    let protocolVersion: Int
    let requestID: UUID
    let operation: PrivilegedOperationKind
    let ruleID: String
    let path: String?
    let expectedIdentity: PrivilegedFileIdentity?
    let targetBytes: UInt64?

    init(
        requestID: UUID = UUID(),
        operation: PrivilegedOperationKind,
        ruleID: String,
        path: String? = nil,
        expectedIdentity: PrivilegedFileIdentity? = nil,
        targetBytes: UInt64? = nil
    ) {
        self.protocolVersion = MemWatchPrivilegedHelperConstants.protocolVersion
        self.requestID = requestID
        self.operation = operation
        self.ruleID = ruleID
        self.path = path
        self.expectedIdentity = expectedIdentity
        self.targetBytes = targetBytes
    }
}

struct PrivilegedOperationResponse: Codable, Sendable {
    let protocolVersion: Int
    let requestID: UUID
    let success: Bool
    let message: String
    let reclaimedBytes: UInt64
    let commandOutput: String?

    init(
        requestID: UUID,
        success: Bool,
        message: String,
        reclaimedBytes: UInt64 = 0,
        commandOutput: String? = nil
    ) {
        self.protocolVersion = MemWatchPrivilegedHelperConstants.protocolVersion
        self.requestID = requestID
        self.success = success
        self.message = message
        self.reclaimedBytes = reclaimedBytes
        self.commandOutput = commandOutput
    }
}

struct PrivilegedScanRequest: Codable, Sendable {
    let protocolVersion: Int
    let requestID: UUID
    let ruleIDs: [String]

    init(requestID: UUID = UUID(), ruleIDs: [String]) {
        self.protocolVersion = MemWatchPrivilegedHelperConstants.protocolVersion
        self.requestID = requestID
        self.ruleIDs = ruleIDs
    }
}

struct PrivilegedScannedItem: Codable, Sendable {
    let ruleID: String
    let path: String?
    let maintenanceIdentifier: String?
    let displayName: String
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let createdAt: Date?
    let modifiedAt: Date?
    let lastAccessedAt: Date?
    let identity: PrivilegedFileIdentity?
    let reason: String
}

struct PrivilegedScanResponse: Codable, Sendable {
    let protocolVersion: Int
    let requestID: UUID
    let items: [PrivilegedScannedItem]
    let issues: [String]

    init(requestID: UUID, items: [PrivilegedScannedItem], issues: [String] = []) {
        self.protocolVersion = MemWatchPrivilegedHelperConstants.protocolVersion
        self.requestID = requestID
        self.items = items
        self.issues = issues
    }
}

struct PrivilegedPingResponse: Codable, Sendable {
    let protocolVersion: Int
    let helperPID: Int32
    let effectiveUID: UInt32
}

@objc protocol MemWatchPrivilegedHelperXPC {
    func ping(withReply reply: @escaping (Data) -> Void)
    func scan(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func execute(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}
