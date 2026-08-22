import Foundation

@main
struct MemoryPressureEstimateTests {
    private static let gib: UInt64 = 1024 * 1024 * 1024
    private static let mib: UInt64 = 1024 * 1024

    static func main() {
        healthyMemoryStaysLow()
        compressedMemoryRaisesEstimate()
        activeSwapOutRaisesEstimate()
        idleSwapAllocationDoesNotRaiseEstimate()
        warningAndCriticalStatesSetFloors()
        estimateAlwaysStaysInRange()

        print("PASS Memory pressure estimate tests")
    }

    private static func healthyMemoryStaysLow() {
        let snapshot = makeSnapshot(
            available: 8 * gib,
            compressed: 1 * gib,
            swapUsed: 0,
            pressure: .normal
        )

        let estimate = MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: 0,
            effectivePressure: .normal
        )

        require(estimate.percent < 20, "Healthy memory should have a low pressure estimate")
    }

    private static func compressedMemoryRaisesEstimate() {
        let lowCompression = makeSnapshot(
            available: 5 * gib,
            compressed: 1 * gib,
            swapUsed: 0,
            pressure: .normal
        )
        let highCompression = makeSnapshot(
            available: 5 * gib,
            compressed: 4 * gib,
            swapUsed: 0,
            pressure: .normal
        )

        let low = MemoryPressureEstimate.calculate(
            snapshot: lowCompression,
            swapOutDeltaBytes: 0,
            effectivePressure: .normal
        )
        let high = MemoryPressureEstimate.calculate(
            snapshot: highCompression,
            swapOutDeltaBytes: 0,
            effectivePressure: .normal
        )

        require(high.percent > low.percent, "Compression should raise the pressure estimate")
    }

    private static func activeSwapOutRaisesEstimate() {
        let snapshot = makeSnapshot(
            available: 5 * gib,
            compressed: 3 * gib,
            swapUsed: 2 * gib,
            pressure: .normal
        )

        let idle = MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: 0,
            effectivePressure: .normal
        )
        let active = MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: 256 * mib,
            effectivePressure: .normal
        )

        require(active.percent > idle.percent, "Recent swap-out traffic should raise the pressure estimate")
    }

    private static func idleSwapAllocationDoesNotRaiseEstimate() {
        let noSwap = makeSnapshot(
            available: 6 * gib,
            compressed: 2 * gib,
            swapUsed: 0,
            pressure: .normal
        )
        let idleSwap = makeSnapshot(
            available: 6 * gib,
            compressed: 2 * gib,
            swapUsed: 6 * gib,
            pressure: .normal
        )

        let first = MemoryPressureEstimate.calculate(
            snapshot: noSwap,
            swapOutDeltaBytes: 0,
            effectivePressure: .normal
        )
        let second = MemoryPressureEstimate.calculate(
            snapshot: idleSwap,
            swapOutDeltaBytes: 0,
            effectivePressure: .normal
        )

        require(first.percent == second.percent, "Idle swap allocation must not inflate memory pressure")
    }

    private static func warningAndCriticalStatesSetFloors() {
        let snapshot = makeSnapshot(
            available: 10 * gib,
            compressed: 512 * mib,
            swapUsed: 0,
            pressure: .normal
        )

        let warning = MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: 0,
            effectivePressure: .warning
        )
        let critical = MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: 0,
            effectivePressure: .critical
        )

        require(warning.percent >= 60, "Warning pressure should floor the estimate at 60%")
        require(critical.percent >= 90, "Critical pressure should floor the estimate at 90%")
    }

    private static func estimateAlwaysStaysInRange() {
        let snapshot = makeSnapshot(
            available: 0,
            compressed: 16 * gib,
            swapUsed: 16 * gib,
            pressure: .critical
        )

        let estimate = MemoryPressureEstimate.calculate(
            snapshot: snapshot,
            swapOutDeltaBytes: UInt64.max,
            effectivePressure: .critical
        )

        require((0...100).contains(estimate.percent), "Pressure estimate must stay within 0...100")
    }

    private static func makeSnapshot(
        available: UInt64,
        compressed: UInt64,
        swapUsed: UInt64,
        pressure: MemoryPressure
    ) -> MemorySnapshot {
        let total = 16 * gib
        return MemorySnapshot(
            timestamp: .now,
            totalBytes: total,
            usedBytes: total > available ? total - available : 0,
            availableBytes: min(available, total),
            freeBytes: 0,
            cachedBytes: available,
            wiredBytes: 2 * gib,
            compressedBytes: min(compressed, total),
            swapTotalBytes: 16 * gib,
            swapUsedBytes: swapUsed,
            swapFreeBytes: 16 * gib > swapUsed ? 16 * gib - swapUsed : 0,
            swapInBytes: 0,
            swapOutBytes: 0,
            pressure: pressure
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
