import Foundation

struct CleanupFileSize: Equatable, Sendable {
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
}

struct CleanupFileSizer: Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func measure(_ url: URL) -> CleanupFileSize {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]

        guard let rootValues = try? url.resourceValues(forKeys: keys) else {
            return CleanupFileSize(logicalBytes: 0, allocatedBytes: 0)
        }

        if rootValues.isSymbolicLink == true {
            return CleanupFileSize(logicalBytes: 0, allocatedBytes: 0)
        }

        if rootValues.isDirectory != true {
            return size(from: rootValues)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return CleanupFileSize(logicalBytes: 0, allocatedBytes: 0)
        }

        var logical: UInt64 = 0
        var allocated: UInt64 = 0

        for case let childURL as URL in enumerator {
            guard let values = try? childURL.resourceValues(forKeys: keys) else { continue }

            if values.isSymbolicLink == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else { continue }
            let childSize = size(from: values)
            logical = addingWithoutOverflow(logical, childSize.logicalBytes)
            allocated = addingWithoutOverflow(allocated, childSize.allocatedBytes)
        }

        return CleanupFileSize(logicalBytes: logical, allocatedBytes: allocated)
    }

    private func size(from values: URLResourceValues) -> CleanupFileSize {
        let logical = positiveUInt64(values.fileSize)
        let allocated = positiveUInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize)
        return CleanupFileSize(
            logicalBytes: logical,
            allocatedBytes: allocated > 0 ? allocated : logical
        )
    }

    private func positiveUInt64(_ value: Int?) -> UInt64 {
        guard let value, value > 0 else { return 0 }
        return UInt64(value)
    }

    private func addingWithoutOverflow(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : value
    }
}
