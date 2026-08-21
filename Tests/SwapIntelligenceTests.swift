import Foundation

@main
struct SwapIntelligenceTests {
    private static let gib: UInt64 = 1_024 * 1_024 * 1_024
    private static let mib: UInt64 = 1_024 * 1_024
    private static let totalRAM: UInt64 = 16 * gib

    static func main() {
        testIdleSwapIsNotAnAlert()
        testTransientSwapWriteDoesNotEscalate()
        testSustainedSwapWritesEscalate()
        testRecoveryRequiresQuietSamples()
        testReadbackIsDistinguishedFromSwapWrites()
        testPressureEscalationUsesHysteresis()
        testCriticalEscalationUsesHysteresis()
        testHistoryIsBounded()

        print("MemWatch swap intelligence tests passed")
    }

    private static func testIdleSwapIsNotAnAlert() {
        let engine = SwapIntelligenceEngine()
        let result = engine.ingest(sample(swapUsed: 2 * gib))

        expect(result.state == .idleSwap, "Allocated but inactive swap must be classified as idle")
    }

    private static func testTransientSwapWriteDoesNotEscalate() {
        let engine = SwapIntelligenceEngine()
        _ = engine.ingest(sample())
        let spike = engine.ingest(sample(swapUsed: 1 * gib, swapOut: 8 * mib))
        let quiet = engine.ingest(sample(swapUsed: 1 * gib))

        expect(spike.state != .activeSwap, "One swap-write spike must not trigger active swap")
        expect(quiet.state != .activeSwap, "A transient spike must clear without an active-swap alert")
    }

    private static func testSustainedSwapWritesEscalate() {
        let engine = SwapIntelligenceEngine()
        _ = engine.ingest(sample(swapUsed: 1 * gib))
        let first = engine.ingest(sample(swapUsed: 1 * gib, swapOut: 8 * mib))
        let second = engine.ingest(sample(swapUsed: 1 * gib, swapOut: 8 * mib))

        expect(first.state == .idleSwap, "First active sample should be held by hysteresis")
        expect(second.state == .activeSwap, "Two consecutive swap-write samples must trigger active swap")
    }

    private static func testRecoveryRequiresQuietSamples() {
        let engine = SwapIntelligenceEngine()
        _ = engine.ingest(sample(swapUsed: 1 * gib))
        _ = engine.ingest(sample(swapUsed: 1 * gib, swapOut: 8 * mib))
        _ = engine.ingest(sample(swapUsed: 1 * gib, swapOut: 8 * mib))

        let quiet1 = engine.ingest(sample(swapUsed: 1 * gib))
        let quiet2 = engine.ingest(sample(swapUsed: 1 * gib))
        let quiet3 = engine.ingest(sample(swapUsed: 1 * gib))

        expect(quiet1.state == .activeSwap, "Recovery should not happen after one quiet sample")
        expect(quiet2.state == .activeSwap, "Recovery should not happen after two quiet samples")
        expect(quiet3.state == .idleSwap, "Three quiet samples should recover to idle swap")
    }

    private static func testReadbackIsDistinguishedFromSwapWrites() {
        let engine = SwapIntelligenceEngine()
        let result = engine.ingest(sample(swapUsed: 1 * gib, swapIn: 16 * mib))

        expect(result.state == .readback, "Swap-in without swap-out must be classified as readback")
    }

    private static func testPressureEscalationUsesHysteresis() {
        let engine = SwapIntelligenceEngine()
        let first = engine.ingest(sample(pressure: .warning))
        let second = engine.ingest(sample(pressure: .warning))

        expect(first.state == .stable, "One warning sample should not immediately escalate")
        expect(second.state == .pressure, "Sustained warning pressure should escalate")
    }

    private static func testCriticalEscalationUsesHysteresis() {
        let engine = SwapIntelligenceEngine()
        let first = engine.ingest(sample(pressure: .critical))
        let second = engine.ingest(sample(pressure: .critical))

        expect(first.state == .stable, "One critical sample should be confirmed before escalation")
        expect(second.state == .critical, "Two critical samples should escalate to critical")
    }

    private static func testHistoryIsBounded() {
        let engine = SwapIntelligenceEngine()
        for index in 0..<20 {
            _ = engine.ingest(sample(timestamp: Date(timeIntervalSince1970: TimeInterval(index * 5))))
        }

        expect(engine.history.count == 12, "The rolling history must stay bounded to 12 samples")
        expect(engine.result.sampleCount == 12, "The public sample count must reflect the bounded history")
    }

    private static func sample(
        timestamp: Date = .now,
        pressure: MemoryPressure = .normal,
        available: UInt64 = 4 * gib,
        compressed: UInt64 = 2 * gib,
        swapUsed: UInt64 = 0,
        swapIn: UInt64 = 0,
        swapOut: UInt64 = 0
    ) -> SwapIntelligenceSample {
        SwapIntelligenceSample(
            timestamp: timestamp,
            pressure: pressure,
            totalBytes: totalRAM,
            availableBytes: available,
            compressedBytes: compressed,
            swapUsedBytes: swapUsed,
            swapInDeltaBytes: swapIn,
            swapOutDeltaBytes: swapOut
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
