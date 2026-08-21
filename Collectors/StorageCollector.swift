import Foundation

final class StorageCollector {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func collect() -> [StorageVolumeSnapshot] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey
        ]

        guard let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        let diskImageMountPaths = Self.mountedDiskImagePaths()
        var seen = Set<String>()
        var volumes: [StorageVolumeSnapshot] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsLocal != false else { continue }

            let mountPath = url.standardizedFileURL.path
            guard Self.shouldIncludeVolume(
                mountPath: mountPath,
                diskImageMountPaths: diskImageMountPaths
            ) else {
                continue
            }

            let totalBytes = positiveUInt64(values.volumeTotalCapacity)
            guard totalBytes > 0 else { continue }

            let importantAvailable = positiveUInt64(values.volumeAvailableCapacityForImportantUsage)
            let ordinaryAvailable = positiveUInt64(values.volumeAvailableCapacity)
            let availableBytes = min(
                importantAvailable > 0 ? importantAvailable : ordinaryAvailable,
                totalBytes
            )

            let identifier = values.volumeUUIDString ?? mountPath
            guard seen.insert(identifier).inserted else { continue }

            let fallbackName = mountPath == "/" ? "Macintosh HD" : url.lastPathComponent
            let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isInternal = values.volumeIsInternal ?? (mountPath == "/")

            volumes.append(
                StorageVolumeSnapshot(
                    id: identifier,
                    name: (name?.isEmpty == false ? name! : fallbackName),
                    mountPath: mountPath,
                    totalBytes: totalBytes,
                    availableBytes: availableBytes,
                    isInternal: isInternal,
                    isReadOnly: values.volumeIsReadOnly ?? false
                )
            )
        }

        return volumes.sorted {
            if $0.isInternal != $1.isInternal {
                return $0.isInternal && !$1.isInternal
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func shouldIncludeVolume(
        mountPath: String,
        diskImageMountPaths: Set<String>
    ) -> Bool {
        let standardized = URL(fileURLWithPath: mountPath).standardizedFileURL.path
        return !diskImageMountPaths.contains(standardized)
    }

    private static func mountedDiskImagePaths() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return []
        }

        var paths = Set<String>()
        for image in images {
            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                guard let mountPoint = entity["mount-point"] as? String else { continue }
                paths.insert(URL(fileURLWithPath: mountPoint).standardizedFileURL.path)
            }
        }
        return paths
    }

    private func positiveUInt64(_ value: Int?) -> UInt64 {
        guard let value, value > 0 else { return 0 }
        return UInt64(value)
    }

    private func positiveUInt64(_ value: Int64?) -> UInt64 {
        guard let value, value > 0 else { return 0 }
        return UInt64(value)
    }
}
