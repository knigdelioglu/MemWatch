import Foundation

@main
struct StorageVolumeFilteringTests {
    static func main() {
        let imageMounts: Set<String> = [
            "/Volumes/MemWatch",
            "/Volumes/Installer Image"
        ]

        precondition(
            !StorageCollector.shouldIncludeVolume(
                mountPath: "/Volumes/MemWatch",
                diskImageMountPaths: imageMounts
            ),
            "Mounted MemWatch DMG must be filtered"
        )

        precondition(
            !StorageCollector.shouldIncludeVolume(
                mountPath: "/Volumes/Installer Image/../Installer Image",
                diskImageMountPaths: imageMounts
            ),
            "Disk-image paths must be standardized before comparison"
        )

        precondition(
            StorageCollector.shouldIncludeVolume(
                mountPath: "/Volumes/Lacie",
                diskImageMountPaths: imageMounts
            ),
            "Physical external storage must remain visible"
        )

        precondition(
            StorageCollector.shouldIncludeVolume(
                mountPath: "/",
                diskImageMountPaths: imageMounts
            ),
            "Internal root storage must remain visible"
        )

        print("PASS Storage disk-image filtering")
    }
}
