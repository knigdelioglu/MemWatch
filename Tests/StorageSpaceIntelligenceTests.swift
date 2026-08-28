import Foundation

@main
struct StorageSpaceIntelligenceTests {
    static func main() {
        let sample = StorageSpaceIntelligence(
            immediateAvailableBytes: 20,
            importantUsageAvailableBytes: 55,
            opportunisticUsageAvailableBytes: 40
        )
        precondition(sample.purgeableEstimateBytes == 35, "Purgeable estimate should be important-usage capacity minus immediately free capacity")

        let noExtra = StorageSpaceIntelligence(
            immediateAvailableBytes: 50,
            importantUsageAvailableBytes: 45,
            opportunisticUsageAvailableBytes: 45
        )
        precondition(noExtra.purgeableEstimateBytes == 0, "Purgeable estimate must never underflow")

        if let live = StorageSpaceIntelligence.startupVolume() {
            precondition(live.importantUsageAvailableBytes >= live.immediateAvailableBytes || live.purgeableEstimateBytes == 0)
        }

        print("PASS APFS storage intelligence")
    }
}
