import Foundation

@main
struct ThermalAggregatorTests {
    private static let aggregator = ThermalAggregator()

    static func main() {
        testValidatedCPUCanonicalPackage()
        testCPUPackageDoesNotMergeClusterMembers()
        testCPUClusterAverageAndHottest()
        testGPUClusterAggregation()
        testContextOnlyAndCandidateSensorsDoNotAggregate()
        testBatteryAndStorageAreCanonicalSingles()
        testInvalidStaleAndUnmappedReadingsDoNotAggregate()
        testCrossSourceAndEpochIsolation()
        testMemoryIsNeverDerived()
        print("PASS Thermal aggregator")
    }

    private static func testValidatedCPUCanonicalPackage() {
        let package = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "cpu-package",
            mapping: ThermalTestFixtures.mapping(
                catalogID: "cpu-package",
                category: .cpu,
                confidence: .validated,
                aggregationRole: .cpuPackage
            ),
            sample: .valid(celsius: 62)
        )
        let aggregate = aggregate(
            category: .cpu,
            readings: [package],
            selectionIDs: ["cpu-package"]
        )

        require(aggregate?.currentCelsius == 62, "CPU package must supply the current value")
        require(aggregate?.averageCelsius == 62, "Single CPU package average must be deterministic")
        require(aggregate?.hottestCelsius == 62, "Single CPU package hottest value must be deterministic")
        require(aggregate?.contributorCatalogIDs == ["cpu-package"], "CPU package contributor must be explicit")
    }

    private static func testCPUPackageDoesNotMergeClusterMembers() {
        let package = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "cpu-package",
            mapping: ThermalTestFixtures.mapping(
                catalogID: "cpu-package",
                category: .cpu,
                confidence: .validated,
                aggregationRole: .cpuPackage
            ),
            sample: .valid(celsius: 60)
        )
        let cluster = (1...2).map { index in
            ThermalTestFixtures.reading(
                source: .ioHID,
                rawIdentifier: "cpu-cluster-\(index)",
                mapping: ThermalTestFixtures.mapping(
                    catalogID: "cpu-cluster-\(index)",
                    category: .cpu,
                    confidence: .validated,
                    aggregationGroup: "cpu-cluster",
                    aggregationRole: .cpuClusterMember
                ),
                sample: .valid(celsius: 90 + Double(index))
            )
        }

        let aggregate = aggregate(
            category: .cpu,
            readings: [package] + cluster,
            selectionIDs: ["cpu-package", "cpu-cluster-1", "cpu-cluster-2"]
        )
        require(aggregate?.currentCelsius == 60, "Validated CPU package must win over cluster members")
        require(aggregate?.contributorCatalogIDs == ["cpu-package"], "Package and cluster readings must not be double-counted")
    }

    private static func testCPUClusterAverageAndHottest() {
        let readings = [40.0, 50.0, 60.0].enumerated().map { index, value in
            ThermalTestFixtures.reading(
                source: .ioHID,
                rawIdentifier: "cpu-cluster-\(index)",
                mapping: ThermalTestFixtures.mapping(
                    catalogID: "cpu-cluster-\(index)",
                    category: .cpu,
                    confidence: .validated,
                    aggregationGroup: "cpu-cluster",
                    aggregationRole: .cpuClusterMember
                ),
                sample: .valid(celsius: value)
            )
        }
        let aggregate = aggregate(
            category: .cpu,
            readings: readings,
            selectionIDs: readings.compactMap(\.mapping.catalogID)
        )
        require(aggregate?.averageCelsius == 50, "CPU cluster average must be arithmetic")
        require(aggregate?.hottestCelsius == 60, "CPU cluster hottest must be maximum")
        require(aggregate?.currentCelsius == 60, "CPU headline current must use hottest")
    }

    private static func testGPUClusterAggregation() {
        let readings = [48.0, 54.0].enumerated().map { index, value in
            ThermalTestFixtures.reading(
                source: .appleSMC,
                rawIdentifier: "gpu-cluster-\(index)",
                mapping: ThermalTestFixtures.mapping(
                    catalogID: "gpu-cluster-\(index)",
                    category: .gpu,
                    confidence: .validated,
                    aggregationGroup: "gpu-cluster",
                    aggregationRole: .gpuClusterMember
                ),
                sample: .valid(celsius: value)
            )
        }
        let aggregate = aggregate(
            category: .gpu,
            readings: readings,
            source: .appleSMC,
            selectionIDs: readings.compactMap(\.mapping.catalogID)
        )
        require(aggregate?.averageCelsius == 51, "GPU cluster average must be arithmetic")
        require(aggregate?.hottestCelsius == 54 && aggregate?.currentCelsius == 54, "GPU hottest must drive current")
    }

    private static func testContextOnlyAndCandidateSensorsDoNotAggregate() {
        let pmu = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "pmu",
            rawName: "PMU tdie4",
            mapping: ThermalTestFixtures.mapping(
                catalogID: "pmu",
                category: .pmu,
                confidence: .medium,
                aggregationRole: .contextOnly
            ),
            sample: .valid(celsius: 44)
        )
        let candidateCPU = ThermalTestFixtures.reading(
            source: .appleSMC,
            rawIdentifier: "Tp01",
            mapping: ThermalTestFixtures.mapping(
                status: .candidate,
                catalogID: "smc-cpu-candidate",
                category: .cpu,
                confidence: .medium,
                aggregationRole: .none
            ),
            sample: .valid(celsius: 55)
        )
        require(aggregate(category: .cpu, readings: [pmu], selectionIDs: ["pmu"]) == nil, "PMU must not produce CPU aggregate")
        require(aggregate(category: .cpu, readings: [candidateCPU], source: .appleSMC, selectionIDs: ["smc-cpu-candidate"]) == nil, "Candidate CPU mapping must not aggregate")
    }

    private static func testBatteryAndStorageAreCanonicalSingles() {
        let battery = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "battery",
            mapping: ThermalTestFixtures.mapping(
                catalogID: "battery",
                category: .battery,
                confidence: .high,
                aggregationRole: .canonicalBattery
            ),
            sample: .valid(celsius: 34)
        )
        let storage = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "storage",
            mapping: ThermalTestFixtures.mapping(
                catalogID: "storage",
                category: .storage,
                confidence: .high,
                aggregationRole: .canonicalStorage
            ),
            sample: .valid(celsius: 41)
        )
        let aggregates = Self.aggregator.aggregate(
            readings: [battery, storage],
            selections: ThermalCategorySourceSelections([
                ThermalTestFixtures.selection(category: .battery, source: .ioHID, catalogEntryIDs: ["battery"], confidence: .high),
                ThermalTestFixtures.selection(category: .storage, source: .ioHID, catalogEntryIDs: ["storage"], confidence: .high)
            ]),
            hardwareEpoch: 1
        )
        require(aggregates[.battery]?.currentCelsius == 34, "Battery current must use the canonical value")
        require(aggregates[.battery]?.averageCelsius == nil && aggregates[.battery]?.hottestCelsius == nil, "Battery must remain a single-sensor aggregate")
        require(aggregates[.storage]?.currentCelsius == 41, "Storage current must use the canonical value")
        require(aggregates[.storage]?.averageCelsius == nil && aggregates[.storage]?.hottestCelsius == nil, "Storage must remain a single-sensor aggregate")
    }

    private static func testInvalidStaleAndUnmappedReadingsDoNotAggregate() {
        let validMapping = ThermalTestFixtures.mapping(
            catalogID: "battery",
            category: .battery,
            confidence: .validated,
            aggregationRole: .canonicalBattery
        )
        let invalid = ThermalTestFixtures.reading(source: .ioHID, rawIdentifier: "invalid", mapping: validMapping, sample: .invalidSample(reason: "decoder"))
        let stale = ThermalTestFixtures.reading(source: .ioHID, rawIdentifier: "stale", mapping: validMapping, sample: .stale(lastKnownCelsius: 35, age: 10))
        let notSampled = ThermalTestFixtures.reading(source: .ioHID, rawIdentifier: "not-sampled", mapping: validMapping, sample: .notSampled)
        require(aggregate(category: .battery, readings: [invalid, stale, notSampled], selectionIDs: ["battery"]) == nil, "Non-current sample states must not aggregate")

        let unmapped = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "unknown",
            mapping: SensorMapping(status: .unmapped, confidence: .unknown, aggregationRole: .none),
            sample: .valid(celsius: 33)
        )
        require(aggregate(category: .battery, readings: [unmapped], selectionIDs: []) == nil, "Unmapped readings must remain raw-only")
    }

    private static func testCrossSourceAndEpochIsolation() {
        let hid = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "hid-storage",
            mapping: ThermalTestFixtures.mapping(catalogID: "hid-storage", category: .storage, confidence: .high, aggregationRole: .canonicalStorage),
            sample: .valid(celsius: 40),
            hardwareEpoch: 1
        )
        let smc = ThermalTestFixtures.reading(
            source: .appleSMC,
            rawIdentifier: "smc-storage",
            mapping: ThermalTestFixtures.mapping(catalogID: "smc-storage", category: .storage, confidence: .high, aggregationRole: .canonicalStorage),
            sample: .valid(celsius: 90),
            hardwareEpoch: 1
        )
        let hidBackend = FakeThermalBackend(
            source: .ioHID,
            status: ThermalTestFixtures.backendStatus(.ioHID),
            readings: [hid]
        )
        let smcBackend = FakeThermalBackend(
            source: .appleSMC,
            status: ThermalTestFixtures.backendStatus(.appleSMC),
            readings: [smc]
        )
        let selection = ThermalTestFixtures.selection(category: .storage, source: .ioHID, catalogEntryIDs: ["hid-storage"], confidence: .high)
        let aggregates = Self.aggregator.aggregate(
            readings: hidBackend.readings + smcBackend.readings,
            selections: ThermalCategorySourceSelections([selection]),
            hardwareEpoch: 1
        )
        require(aggregates[.storage]?.currentCelsius == 40, "One category must never merge two backend sources")

        let oldReading = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "old-storage",
            mapping: hid.mapping,
            sample: .valid(celsius: 41),
            hardwareEpoch: 0
        )
        require(Self.aggregator.aggregate(readings: [oldReading], selections: ThermalCategorySourceSelections([selection]), hardwareEpoch: 1)[.storage] == nil, "Old hardware epoch must not be accepted")

        let nextSelection = ThermalTestFixtures.selection(category: .storage, source: .ioHID, catalogEntryIDs: ["hid-storage"], confidence: .high, generation: 2)
        let nextAggregate = Self.aggregator.aggregate(readings: [hid], selections: ThermalCategorySourceSelections([nextSelection]), hardwareEpoch: 1)[.storage]
        require(nextAggregate?.selectionGeneration == 2, "A source selection generation change must flow into new aggregates")
        require(nextAggregate?.selectionGeneration != aggregates[.storage]?.selectionGeneration, "An old-generation aggregate must not be reused")
    }

    private static func testMemoryIsNeverDerived() {
        let pmu = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "pmu",
            mapping: ThermalTestFixtures.mapping(catalogID: "pmu", category: .pmu, confidence: .medium, aggregationRole: .contextOnly),
            sample: .valid(celsius: 45)
        )
        let soc = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "soc",
            mapping: ThermalTestFixtures.mapping(catalogID: "soc", category: .soc, confidence: .medium, aggregationRole: .none),
            sample: .valid(celsius: 46)
        )
        let storage = ThermalTestFixtures.reading(
            source: .ioHID,
            rawIdentifier: "storage",
            mapping: ThermalTestFixtures.mapping(catalogID: "storage", category: .storage, confidence: .high, aggregationRole: .canonicalStorage),
            sample: .valid(celsius: 47)
        )
        let selections = ThermalCategorySourceSelections([
            ThermalTestFixtures.selection(category: .memory, source: .ioHID, catalogEntryIDs: ["pmu", "soc", "storage"], confidence: .high)
        ])
        require(Self.aggregator.aggregate(readings: [pmu, soc, storage], selections: selections, hardwareEpoch: 1)[.memory] == nil, "PMU, SoC, and storage must never become memory temperature")
    }

    private static func aggregate(
        category: TemperatureSensorCategory,
        readings: [TemperatureSensorReading],
        source: TemperatureSensorSource = .ioHID,
        selectionIDs: [String],
        generation: UInt64 = 1
    ) -> TemperatureAggregate? {
        let selection = ThermalTestFixtures.selection(
            category: category,
            source: source,
            catalogEntryIDs: selectionIDs,
            confidence: .validated,
            generation: generation
        )
        return Self.aggregator.aggregate(
            category: category,
            readings: readings,
            selection: selection,
            hardwareEpoch: 1
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
