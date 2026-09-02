import Darwin
import Foundation

/// The identity captured at scan time and rechecked through an open parent
/// directory immediately before an unlink/rmdir operation. The optional
/// metadata fields keep older protocol fixtures readable while allowing new
/// scans to detect in-place file replacement as well as inode replacement.
struct CleanupSecureNodeIdentity: Codable, Equatable, Sendable {
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

enum CleanupSecureRemovalError: LocalizedError, Equatable {
    case invalidPath
    case identityChanged
    case targetMissing
    case symbolicLink(String)
    case unsupportedFileType(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Cleanup target path is invalid or points at a filesystem root."
        case .identityChanged:
            return "Cleanup target changed during secure deletion validation."
        case .targetMissing:
            return "Cleanup target no longer exists."
        case .symbolicLink(let path):
            return "Symbolic links are never traversed or removed: " + path
        case .unsupportedFileType(let path):
            return "Only regular files and directories can be removed: " + path
        case .operationFailed(let message):
            return message
        }
    }
}

/// Descriptor-relative removal for cleanup targets. It does not follow
/// symlinks, rejects special files, and never re-resolves a child through a
/// process-global path while recursively deleting a directory.
enum CleanupSecureFileOperations {
    static func identity(atPath path: String) -> CleanupSecureNodeIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return identity(from: info)
    }

    static func remove(
        atPath rawPath: String,
        expectedIdentity: CleanupSecureNodeIdentity,
        cancellationCheck: () throws -> Void = {}
    ) throws {
        try cancellationCheck()
        guard rawPath.hasPrefix("/") else { throw CleanupSecureRemovalError.invalidPath }
        let path = canonicalSystemAlias(
            URL(fileURLWithPath: rawPath).standardizedFileURL.path
        )
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, path != "/" else {
            throw CleanupSecureRemovalError.invalidPath
        }

        let parentFD = try openDirectoryChain(components: Array(components.dropLast()))
        defer { close(parentFD) }

        let name = components[components.count - 1]
        let current = try entryIdentity(parentFD: parentFD, name: name, path: path)
        guard matches(current, expected: expectedIdentity) else {
            throw CleanupSecureRemovalError.identityChanged
        }
        try ensureRemovable(current, path: path)

        if isDirectory(current.mode) {
            let targetFD = try openDirectory(parentFD: parentFD, name: name, path: path)
            defer { close(targetFD) }

            var openedInfo = stat()
            guard fstat(targetFD, &openedInfo) == 0 else {
                throw operationError("Could not inspect " + path)
            }
            let openedIdentity = identity(from: openedInfo)
            guard matches(openedIdentity, expected: expectedIdentity) else {
                throw CleanupSecureRemovalError.identityChanged
            }

            // Preflight the complete tree before mutating it so a symlink or
            // special file discovered deep in the tree cannot be silently
            // traversed or removed. Cancellation is honored throughout this
            // read-only phase. Once it succeeds, the candidate is treated as
            // one non-cancellable mutation boundary and is removed completely.
            try validateDirectoryTree(fd: targetFD, parentPath: path, cancellationCheck: cancellationCheck)
            try removeDirectoryContents(fd: targetFD, parentPath: path)
            // Directory metadata legitimately changes while its contents are
            // removed. Keep the stable inode/owner/mode check for the final
            // parent unlink, while file targets retain size/mtime checking.
            try verifyEntry(parentFD: parentFD, name: name, path: path, expected: stableIdentity(expectedIdentity))
            try unlink(parentFD: parentFD, name: name, flags: AT_REMOVEDIR, path: path)
        } else {
            try verifyEntry(parentFD: parentFD, name: name, path: path, expected: expectedIdentity)
            try unlink(parentFD: parentFD, name: name, flags: 0, path: path)
        }

        var remaining = stat()
        if fstatat(parentFD, name, &remaining, AT_SYMLINK_NOFOLLOW) == 0 {
            throw CleanupSecureRemovalError.operationFailed("Secure deletion completed but the target still exists: " + path)
        }
        guard errno == ENOENT else { throw operationError("Could not verify removal of " + path) }
    }

    /// Atomically moves a user-owned target into a caller-selected Trash
    /// directory without following a path after the identity check. The
    /// destination is created with an exclusive name so an existing Trash
    /// entry can never be overwritten.
    static func moveToTrash(
        atPath rawPath: String,
        expectedIdentity: CleanupSecureNodeIdentity,
        trashDirectoryPath rawTrashDirectoryPath: String
    ) throws {
        guard rawPath.hasPrefix("/"), rawTrashDirectoryPath.hasPrefix("/") else {
            throw CleanupSecureRemovalError.invalidPath
        }

        let path = canonicalSystemAlias(URL(fileURLWithPath: rawPath).standardizedFileURL.path)
        let trashDirectoryPath = canonicalSystemAlias(
            URL(fileURLWithPath: rawTrashDirectoryPath, isDirectory: true).standardizedFileURL.path
        )
        guard path != "/",
              trashDirectoryPath != "/",
              isSupportedTrashDirectory(trashDirectoryPath) else {
            throw CleanupSecureRemovalError.invalidPath
        }

        guard path != trashDirectoryPath,
              !path.hasPrefix(trashDirectoryPath + "/") else {
            throw CleanupSecureRemovalError.invalidPath
        }

        let targetComponents = path.split(separator: "/").map(String.init)
        let trashComponents = trashDirectoryPath.split(separator: "/").map(String.init)
        guard !targetComponents.isEmpty, !trashComponents.isEmpty else {
            throw CleanupSecureRemovalError.invalidPath
        }

        let targetParentFD = try openDirectoryChain(components: Array(targetComponents.dropLast()))
        defer { close(targetParentFD) }

        let name = targetComponents[targetComponents.count - 1]
        let current = try entryIdentity(parentFD: targetParentFD, name: name, path: path)
        guard matches(current, expected: expectedIdentity) else {
            throw CleanupSecureRemovalError.identityChanged
        }
        try ensureRemovable(current, path: path)

        let trashFD = try openDirectoryChain(components: trashComponents, createMissing: true)
        defer { close(trashFD) }
        var trashInfo = stat()
        guard fstat(trashFD, &trashInfo) == 0,
              UInt64(trashInfo.st_dev) == current.deviceID else {
            throw CleanupSecureRemovalError.operationFailed("Cleanup target and Trash are on different volumes")
        }

        for _ in 0..<8 {
            let destinationName = name + ".memwatch-" + UUID().uuidString
            let result = destinationName.withCString { destination in
                name.withCString { source in
                    renameatx_np(targetParentFD, source, trashFD, destination, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 {
                let destinationPath = trashDirectoryPath + "/" + destinationName
                let movedIdentity = try entryIdentity(
                    parentFD: trashFD,
                    name: destinationName,
                    path: destinationPath
                )
                guard matches(movedIdentity, expected: expectedIdentity) else {
                    let restored = destinationName.withCString { destination in
                        name.withCString { source in
                            renameatx_np(trashFD, destination, targetParentFD, source, UInt32(RENAME_EXCL))
                        }
                    }
                    if restored == 0 {
                        throw CleanupSecureRemovalError.identityChanged
                    }
                    throw CleanupSecureRemovalError.operationFailed(
                        "Cleanup target changed while moving to Trash; the replacement remains in Trash."
                    )
                }
                return
            }
            let errorNumber = errno
            if errorNumber == EEXIST { continue }
            throw operationError("Could not move cleanup target to Trash", errorNumber: errorNumber)
        }

        throw CleanupSecureRemovalError.operationFailed("Could not allocate a unique Trash destination for " + path)
    }

    private static func openDirectoryChain(components: [String], createMissing: Bool = false) throws -> Int32 {
        let rootFD = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard rootFD >= 0 else { throw operationError("Could not open the filesystem root") }
        var currentFD = rootFD

        for component in components {
            var nextFD = component.withCString {
                Darwin.openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            if nextFD < 0, createMissing, errno == ENOENT {
                let created = component.withCString {
                    mkdirat(currentFD, $0, mode_t(0o700))
                }
                guard created == 0 || errno == EEXIST else {
                    let errorNumber = errno
                    close(currentFD)
                    throw operationError("Could not create secure directory component " + component, errorNumber: errorNumber)
                }
                nextFD = component.withCString {
                    Darwin.openat(currentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
            }
            guard nextFD >= 0 else {
                let errorNumber = errno
                close(currentFD)
                throw operationError("Could not securely open parent directory component " + component, errorNumber: errorNumber)
            }
            close(currentFD)
            currentFD = nextFD
        }
        return currentFD
    }

    private static func openDirectory(parentFD: Int32, name: String, path: String) throws -> Int32 {
        let fd = name.withCString {
            Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fd >= 0 else { throw operationError("Could not securely open directory " + path) }
        return fd
    }

    private static func entryIdentity(parentFD: Int32, name: String, path: String) throws -> CleanupSecureNodeIdentity {
        var info = stat()
        let result = name.withCString { fstatat(parentFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        guard result == 0 else {
            if errno == ENOENT { throw CleanupSecureRemovalError.targetMissing }
            throw operationError("Could not inspect cleanup target " + path)
        }
        return identity(from: info)
    }

    private static func verifyEntry(
        parentFD: Int32,
        name: String,
        path: String,
        expected: CleanupSecureNodeIdentity
    ) throws {
        let current = try entryIdentity(parentFD: parentFD, name: name, path: path)
        guard matches(current, expected: expected) else {
            throw CleanupSecureRemovalError.identityChanged
        }
        try ensureRemovable(current, path: path)
    }

    private static func verifyOpenedDirectory(
        _ fd: Int32,
        expected: CleanupSecureNodeIdentity,
        path: String
    ) throws {
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw operationError("Could not inspect directory " + path)
        }
        let opened = identity(from: info)
        guard matches(opened, expected: stableIdentity(expected)) else {
            throw CleanupSecureRemovalError.identityChanged
        }
    }

    private static func validateDirectoryTree(
        fd: Int32,
        parentPath: String,
        cancellationCheck: () throws -> Void
    ) throws {
        try forEachEntry(in: fd) { name in
            try cancellationCheck()
            let path = parentPath + "/" + name
            let child = try entryIdentity(parentFD: fd, name: name, path: path)
            try ensureRemovable(child, path: path)
            if isDirectory(child.mode) {
                let childFD = try openDirectory(parentFD: fd, name: name, path: path)
                defer { close(childFD) }
                try verifyOpenedDirectory(childFD, expected: child, path: path)
                try validateDirectoryTree(fd: childFD, parentPath: path, cancellationCheck: cancellationCheck)
            }
        }
        try cancellationCheck()
    }

    private static func removeDirectoryContents(
        fd: Int32,
        parentPath: String
    ) throws {
        var names: [String] = []
        try forEachEntry(in: fd) { names.append($0) }

        for name in names {
            let path = parentPath + "/" + name
            let child: CleanupSecureNodeIdentity
            do {
                child = try entryIdentity(parentFD: fd, name: name, path: path)
            } catch CleanupSecureRemovalError.targetMissing {
                // A concurrent actor already removed this child. It is safe
                // to continue because the anchored directory is still the
                // same object we opened for this cleanup.
                continue
            }
            try ensureRemovable(child, path: path)

            if isDirectory(child.mode) {
                let childFD = try openDirectory(parentFD: fd, name: name, path: path)
                defer { close(childFD) }
                try verifyOpenedDirectory(childFD, expected: child, path: path)
                try removeDirectoryContents(fd: childFD, parentPath: path)
                try verifyEntry(parentFD: fd, name: name, path: path, expected: stableIdentity(child))
                try unlink(parentFD: fd, name: name, flags: AT_REMOVEDIR, path: path)
            } else {
                try verifyEntry(parentFD: fd, name: name, path: path, expected: child)
                try unlink(parentFD: fd, name: name, flags: 0, path: path)
            }
        }
    }

    private static func forEachEntry(in fd: Int32, _ body: (String) throws -> Void) throws {
        // dup() shares the directory stream offset with the original
        // descriptor. Open "." relative to the anchored descriptor instead,
        // so preflight and deletion passes each receive an independent stream.
        let duplicate = ".".withCString {
            Darwin.openat(fd, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard duplicate >= 0 else { throw operationError("Could not duplicate directory descriptor") }
        guard let directory = fdopendir(duplicate) else {
            close(duplicate)
            throw operationError("Could not enumerate directory descriptor")
        }
        defer { closedir(directory) }

        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            try body(name)
        }
    }

    private static func unlink(parentFD: Int32, name: String, flags: Int32, path: String) throws {
        let result = name.withCString { unlinkat(parentFD, $0, flags) }
        guard result == 0 else { throw operationError("Could not remove " + path) }
    }

    private static func ensureRemovable(_ identity: CleanupSecureNodeIdentity, path: String) throws {
        if (identity.mode & UInt32(S_IFMT)) == UInt32(S_IFLNK) {
            throw CleanupSecureRemovalError.symbolicLink(path)
        }
        guard isRegularFile(identity.mode) || isDirectory(identity.mode) else {
            throw CleanupSecureRemovalError.unsupportedFileType(path)
        }
    }

    private static func identity(from info: stat) -> CleanupSecureNodeIdentity {
        CleanupSecureNodeIdentity(
            deviceID: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            ownerUID: UInt32(info.st_uid),
            mode: UInt32(info.st_mode),
            sizeBytes: UInt64(max(0, info.st_size)),
            modificationTimeNanoseconds: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        )
    }

    private static func matches(_ actual: CleanupSecureNodeIdentity, expected: CleanupSecureNodeIdentity) -> Bool {
        guard actual.deviceID == expected.deviceID,
              actual.inode == expected.inode,
              actual.ownerUID == expected.ownerUID,
              actual.mode == expected.mode else { return false }
        if let expectedSize = expected.sizeBytes, actual.sizeBytes != expectedSize { return false }
        if let expectedModification = expected.modificationTimeNanoseconds,
           actual.modificationTimeNanoseconds != expectedModification { return false }
        return true
    }

    private static func stableIdentity(_ identity: CleanupSecureNodeIdentity) -> CleanupSecureNodeIdentity {
        CleanupSecureNodeIdentity(
            deviceID: identity.deviceID,
            inode: identity.inode,
            ownerUID: identity.ownerUID,
            mode: identity.mode
        )
    }

    private static func isDirectory(_ mode: UInt32) -> Bool {
        (mode & UInt32(S_IFMT)) == UInt32(S_IFDIR)
    }

    private static func isRegularFile(_ mode: UInt32) -> Bool {
        (mode & UInt32(S_IFMT)) == UInt32(S_IFREG)
    }

    private static func operationError(_ action: String, errorNumber: Int32? = nil) -> CleanupSecureRemovalError {
        let number = errorNumber ?? errno
        return CleanupSecureRemovalError.operationFailed(action + ": " + String(cString: strerror(number)))
    }

    private static func canonicalSystemAlias(_ path: String) -> String {
        // macOS exposes /var and /tmp as stable aliases to /private/var and
        // /private/tmp. Descriptor traversal must use the real directory so
        // O_NOFOLLOW can reject unexpected symlinks without rejecting these
        // platform-owned aliases.
        if path == "/var" || path.hasPrefix("/var/") {
            return "/private" + path
        }
        if path == "/tmp" || path.hasPrefix("/tmp/") {
            return "/private" + path
        }
        return path
    }

    private static func isSupportedTrashDirectory(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let last = components.last else { return false }
        if last == ".Trash" { return true }
        guard components.count >= 2,
              components[components.count - 2] == ".Trashes" else { return false }
        return last == String(getuid())
    }
}
