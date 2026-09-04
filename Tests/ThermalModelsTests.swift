import Foundation

@main
struct ThermalModelsTests {
    static func main() {
        testCategoriesAndSources()
        testMappingAndMeasurementStatesAreIndependent()
        testSnapshotCarriesEpochAndGenerationContracts()
        print("PASS Thermal domain models")
    }

    private static func testCategoriesAndSources() {
        let sources: [TemperatureSensorSource] = [.ioHID, .appleSMC]
        require(sources.count == 2, "Phase 1 must expose exactly two thermal sources")
        require(TemperatureSensorSource.ioHID.rawValue == "ioHID", "IOHID source raw value must be stable")
        require(TemperatureSensorSource.appleSMC.rawValue == "appleSMC", "AppleSMC source raw value must be stable")
        require(TemperatureSensorCategory.allCases.contains(.memoryController), "Memory controller must be a distinct category")
        require(!TemperatureSensorCategory.pmu.isUserFacingAggregate, "PMU must remain diagnostic-only")
        require(
            SensorConfidence.unknown < SensorConfidence.low
                && SensorConfidence.low < SensorConfidence.medium
                && SensorConfidence.medium < SensorConfidence.high
                && SensorConfidence.high < SensorConfidence.validated,
            "Confidence ordering must be semantic"
        )
    }

    private static func testMappingAndMeasurementStatesAreIndependent() {
        let mapping = SensorMapping(
            status: .unmapped,
            catalogID: nil,
            category: nil,
            confidence: .unknown,
            aggregationRole: .none
        )
        let reading = TemperatureSensorReading(
            identity: ThermalTestFixtures.identity(
                source: .ioHID,
                rawIdentifier: "sensor-1",
                rawName: "unclassified"
            ),
            mapping: mapping,
            sample: .valid(celsius: 0),
            timestamp: ThermalTestFixtures.timestamp,
            hardwareEpoch: 1
        )

        require(reading.mapping.status == .unmapped, "Unmapped must be mapping state")
        require(reading.sample.status == .valid, "A valid measurement must remain valid when mapping is unknown")
        require(reading.sample.validCelsius == 0, "Zero Celsius must remain a real value")

        let stale = TemperatureSample.stale(lastKnownCelsius: 42, age: 5)
        require(stale.status == .stale, "Stale status must be derived from the sample outcome")
        require(stale.validCelsius == nil, "Stale samples must not expose a current value")
    }

    private static func testSnapshotCarriesEpochAndGenerationContracts() {
        let selection = ThermalTestFixtures.selection(
            category: .battery,
            source: .ioHID,
            catalogEntryIDs: ["battery"],
            confidence: .validated,
            generation: 4
        )
        let aggregate = TemperatureAggregate(
            category: .battery,
            source: .ioHID,
            currentCelsius: 34,
            averageCelsius: nil,
            hottestCelsius: nil,
            contributorCatalogIDs: ["battery"],
            hardwareEpoch: 2,
            selectionGeneration: 4
        )
        let snapshot = ThermalSnapshot(
            timestamp: ThermalTestFixtures.timestamp,
            hardwareEpoch: 2,
            backendStatuses: [:],
            categorySourceSelections: ThermalCategorySourceSelections([selection]),
            categoryAvailability: .empty,
            aggregates: ThermalAggregates([aggregate]),
            readings: []
        )

        require(snapshot.accepts(aggregate: aggregate), "Aggregate must match both epoch and selection generation")
        require(!snapshot.accepts(reading: ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "old",
            mapping: SensorMapping(status: .mapped, category: .battery, confidence: .validated, aggregationRole: .canonicalBattery),
            sample: .valid(celsius: 34),
            hardwareEpoch: 1
        )), "Snapshot must reject readings from an older hardware epoch")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
