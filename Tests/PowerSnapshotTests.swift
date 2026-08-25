import Foundation

@main
struct PowerSnapshotTests {
    static func main() {
        testWattCalculationPreservesDirection()
        testBatteryDischargeClassification()
        testDirectChargingTelemetry()
        testDerivedChargingLoad()
        testBatteryAssistOnUndersizedAdapter()
        testIdleACShowsRealSystemDraw()
        testInvalidTelemetry()
        print("MemWatch power snapshot tests passed")
    }

    private static func testWattCalculationPreservesDirection() {
        let signed = PowerSnapshot.signedWatts(
            currentMilliAmps: -2_000,
            voltageMilliVolts: 12_000
        )
        let absolute = PowerSnapshot.watts(
            currentMilliAmps: -2_000,
            voltageMilliVolts: 12_000
        )

        precondition(abs((signed ?? 0) + 24.0) < 0.0001, "Discharge must remain negative")
        precondition(abs((absolute ?? 0) - 24.0) < 0.0001, "2 A × 12 V must equal 24 W")
    }

    private static func testBatteryDischargeClassification() {
        let snapshot = makeSnapshot(
            source: .battery,
            isCharging: false,
            signedBatteryWatts: -18.5,
            systemInputWatts: nil,
            measuredSystemLoadWatts: nil
        )

        precondition(snapshot.flow == .discharging)
        precondition(snapshot.observableMetricName == "Mac draw")
        precondition(snapshot.systemLoadWatts == 18.5)
        precondition(snapshot.batteryDischargeWatts == 18.5)
    }

    private static func testDirectChargingTelemetry() {
        let snapshot = makeSnapshot(
            source: .ac,
            isCharging: true,
            signedBatteryWatts: 22.0,
            systemInputWatts: 60.0,
            measuredSystemLoadWatts: 38.0
        )

        precondition(snapshot.flow == .charging)
        precondition(snapshot.adapterInputWatts == 60.0)
        precondition(snapshot.batteryChargeWatts == 22.0)
        precondition(snapshot.systemLoadWatts == 38.0)
        precondition(snapshot.telemetryCoverage == .detailed)
    }

    private static func testDerivedChargingLoad() {
        let snapshot = makeSnapshot(
            source: .ac,
            isCharging: true,
            signedBatteryWatts: 22.0,
            systemInputWatts: 60.0,
            measuredSystemLoadWatts: nil
        )

        precondition(snapshot.systemLoadWatts == 38.0)
        precondition(snapshot.telemetryCoverage == .derived)
    }

    private static func testBatteryAssistOnUndersizedAdapter() {
        let snapshot = makeSnapshot(
            source: .ac,
            isCharging: false,
            signedBatteryWatts: -12.0,
            systemInputWatts: 28.0,
            measuredSystemLoadWatts: nil
        )

        precondition(snapshot.flow == .discharging)
        precondition(snapshot.adapterInputWatts == 28.0)
        precondition(snapshot.batteryDischargeWatts == 12.0)
        precondition(snapshot.systemLoadWatts == 40.0, "28 W adapter + 12 W battery must supply 40 W Mac load")
    }

    private static func testIdleACShowsRealSystemDraw() {
        let snapshot = makeSnapshot(
            source: .ac,
            isCharging: false,
            signedBatteryWatts: 0,
            systemInputWatts: 14.0,
            measuredSystemLoadWatts: 14.0
        )

        precondition(snapshot.flow == .idle)
        precondition(snapshot.observableWatts == 14.0)
    }

    private static func testInvalidTelemetry() {
        precondition(PowerSnapshot.signedWatts(currentMilliAmps: 1_000, voltageMilliVolts: nil) == nil)
        precondition(PowerSnapshot.signedWatts(currentMilliAmps: .infinity, voltageMilliVolts: 12_000) == nil)
        precondition(PowerSnapshot.signedWatts(currentMilliAmps: 1_000, voltageMilliVolts: 0) == nil)
    }

    private static func makeSnapshot(
        source: PowerSourceKind,
        isCharging: Bool,
        signedBatteryWatts: Double?,
        systemInputWatts: Double?,
        measuredSystemLoadWatts: Double?
    ) -> PowerSnapshot {
        PowerSnapshot(
            timestamp: Date(),
            source: source,
            batteryPercent: 50,
            isCharging: isCharging,
            isCharged: false,
            currentMilliAmps: 1_500,
            voltageMilliVolts: 12_000,
            signedBatteryWatts: signedBatteryWatts,
            systemInputWatts: systemInputWatts,
            measuredSystemLoadWatts: measuredSystemLoadWatts,
            adapterRatedWatts: 70,
            adapterCurrentMilliAmps: nil,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil
        )
    }
}
