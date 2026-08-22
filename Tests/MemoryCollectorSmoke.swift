import Foundation

@main
struct MemoryCollectorSmoke {
    static func main() {
        let snapshot = MemoryCollector().collect()

        precondition(snapshot.totalBytes > 0, "Total RAM must be greater than zero")
        precondition(snapshot.usedBytes <= snapshot.totalBytes, "Used RAM cannot exceed total RAM")
        precondition(snapshot.availableBytes <= snapshot.totalBytes, "Available RAM cannot exceed total RAM")
        precondition(snapshot.activeBytes <= snapshot.totalBytes, "Active RAM cannot exceed total RAM")
        precondition(snapshot.wiredBytes <= snapshot.totalBytes, "Wired RAM cannot exceed total RAM")
        precondition(snapshot.compressedBytes <= snapshot.totalBytes, "Compressed RAM cannot exceed total RAM")
        precondition(snapshot.swapUsedBytes <= snapshot.swapTotalBytes || snapshot.swapTotalBytes == 0, "Swap used cannot exceed swap total")

        print("MemWatch collector smoke test passed")
        print("RAM: \(snapshot.usedBytes)/\(snapshot.totalBytes)")
        print("Active: \(snapshot.activeBytes)")
        print("Compressed: \(snapshot.compressedBytes)")
        print("Wired: \(snapshot.wiredBytes)")
        print("Swap: \(snapshot.swapUsedBytes)/\(snapshot.swapTotalBytes)")
        print("Swap-in cumulative: \(snapshot.swapInBytes)")
        print("Swap-out cumulative: \(snapshot.swapOutBytes)")
    }
}
