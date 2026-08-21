import Foundation

@main
struct StorageCollectorSmoke {
    static func main() {
        let volumes = StorageCollector().collect()

        precondition(!volumes.isEmpty, "At least one local storage volume must be detected")
        precondition(volumes.contains(where: { $0.isInternal }), "An internal storage volume must be detected")

        for volume in volumes {
            precondition(volume.totalBytes > 0, "Storage total capacity must be greater than zero")
            precondition(volume.availableBytes <= volume.totalBytes, "Free storage cannot exceed total capacity")
            precondition(volume.usedBytes <= volume.totalBytes, "Used storage cannot exceed total capacity")
            precondition((0...100).contains(volume.usagePercent), "Storage usage percent must be in range")
        }

        print("MemWatch storage collector smoke test passed")
        for volume in volumes {
            print("\(volume.isInternal ? "internal" : "external"): \(volume.name) \(volume.usedBytes)/\(volume.totalBytes) health=\(volume.health.rawValue)")
        }
    }
}
