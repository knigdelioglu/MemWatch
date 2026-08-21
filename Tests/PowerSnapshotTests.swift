import Foundation

@main
struct PowerSnapshotTests {
    static func main() {
        testWattCalculation()
        testBatteryDischargeClassification()
        testChargingClassification()
        testIdleACDoesNotInventSystemDraw()
        testInvalidTelemetry()
        print("MemWatch power snapshot tests passed")
    }

    private static func testWattCalculation() {
        let watts = PowerSnapshot.watts(
            currentMilliAmps: -2_000,
            voltageMilliVolts: 12_000
        )
        precondition(abs((watts ?? 0) - 24.0) < 0.0001, "2 A × 12 V must equal 24 W")
    }

    private static func testBatteryDischargeClassification() {
        let snapshot = makeSnapshot(
            source: .battery,
            isCharging: false,
            watts: 18.5
        )
        precondition(snapshot.flow == .discharging)
        precondition(snapshot.observableMetricName == "Mac draw")
        precondition(snapshot.observableWatts == 18.5)
    }

    private static func testChargingClassification() {
        let snapshot = makeSnapshot(
            source: .ac,
            isCharging: true,
            watts: 22.0
        )
        precondition(snapshot.flow == .charging)
        precondition(snapshot.observableMetricName == "Battery charge")
        precondition(snapshot.observableWatts == 22.0)
    }

    private static func testIdleACDoesNotInventSystemDraw() {
        let snapshot = makeSnapshot(
            source: .ac,
            isCharging: false,
            watts: 14.0
        )
        precondition(snapshot.flow == .idle)
        precondition(snapshot.observableWatts == 0)
    }

    private static func testInvalidTelemetry() {
        precondition(PowerSnapshot.watts(currentMilliAmps: 1_000, voltageMilliVolts: nil) == nil)
        precondition(PowerSnapshot.watts(currentMilliAmps: .infinity, voltageMilliVolts: 12_000) == nil)
        precondition(PowerSnapshot.watts(currentMilliAmps: 1_000, voltageMilliVolts: 0) == nil)
    }

    private static func makeSnapshot(
        source: PowerSourceKind,
        isCharging: Bool,
        watts: Double?
    ) -> PowerSnapshot {
        PowerSnapshot(
            timestamp: Date(),
            source: source,
            batteryPercent: 50,
            isCharging: isCharging,
            isCharged: false,
            currentMilliAmps: 1_500,
            voltageMilliVolts: 12_000,
            batteryFlowWatts: watts,
            adapterRatedWatts: 70,
            adapterCurrentMilliAmps: nil,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil
        )
    }
}
