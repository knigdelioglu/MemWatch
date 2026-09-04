import Foundation

@main
struct SensorCatalogTests {
    static func main() {
        let catalog = SensorCatalog.m4Initial

        testStorage(catalog)
        testBattery(catalog)
        testPMUIsDiagnosticOnly(catalog)
        testSMCPrefixesRemainCandidates(catalog)
        testCatalogMatchingIsDeterministic(catalog)

        print("PASS Sensor catalog")
    }

    private static func testStorage(_ catalog: SensorCatalog) {
        let identity = ThermalTestFixtures.identity(
            source: .ioHID,
            rawIdentifier: "LocationID=storage",
            rawName: "NAND CH0 temp",
            serviceClass: "AppleEmbeddedNVMeTemperatureSensor"
        )
        let entries = catalog.entries(matching: identity)
        require(entries.count == 1, "M4 storage identity must have one deterministic mapping")
        require(entries[0].mapping.category == .storage, "NAND CH0 temp must map to storage")
        require(entries[0].mapping.confidence == .high, "Storage mapping must be high confidence")
        require(entries[0].mapping.aggregationRole == .canonicalStorage, "Storage mapping must have a canonical role")
        require(entries[0].mapping.displayName == "Internal storage sensor", "Storage label must avoid unsupported SSD semantics")

        let otherChannel = ThermalTestFixtures.identity(
            source: .ioHID,
            rawIdentifier: "LocationID=storage-1",
            rawName: "NAND CH1 temp",
            serviceClass: "AppleEmbeddedNVMeTemperatureSensor"
        )
        require(catalog.entries(matching: otherChannel).isEmpty, "Only the evidenced NAND CH0 identity may be mapped initially")
    }

    private static func testBattery(_ catalog: SensorCatalog) {
        let identity = ThermalTestFixtures.identity(
            source: .ioHID,
            rawIdentifier: "LocationID=battery",
            rawName: "gas gauge battery"
        )
        let mapping = catalog.mapping(for: identity)
        require(mapping?.category == .battery, "Gas gauge battery must map to battery")
        require(mapping?.confidence == .high, "Correlated gas gauge battery evidence must remain high-confidence")
        require(mapping?.aggregationRole == .canonicalBattery, "Battery mapping must have a canonical role")
    }

    private static func testPMUIsDiagnosticOnly(_ catalog: SensorCatalog) {
        let identity = ThermalTestFixtures.identity(
            source: .ioHID,
            rawIdentifier: "LocationID=pmu",
            rawName: "PMU tdie4",
            serviceClass: "AppleARMPMUTempSensor"
        )
        guard let mapping = catalog.mapping(for: identity) else {
            fail("PMU tdie identity must be retained in the catalog")
        }
        require(mapping.category == .pmu, "PMU tdie must not be relabeled as CPU")
        require(mapping.aggregationRole == .contextOnly, "PMU must remain context-only")
        require(mapping.confidence == .medium, "PMU semantic confidence must remain medium")
    }

    private static func testSMCPrefixesRemainCandidates(_ catalog: SensorCatalog) {
        let cpuCandidate = ThermalTestFixtures.identity(source: .appleSMC, rawIdentifier: "Tp01")
        let gpuCandidate = ThermalTestFixtures.identity(source: .appleSMC, rawIdentifier: "Tg02")
        let memoryCandidate = ThermalTestFixtures.identity(source: .appleSMC, rawIdentifier: "Tm90")

        for identity in [cpuCandidate, gpuCandidate, memoryCandidate] {
            guard let mapping = catalog.mapping(for: identity) else {
                fail("SMC prefix must be represented as a candidate")
            }
            require(mapping.status == .candidate, "SMC prefix alone must not become mapped")
            require(mapping.confidence != .validated, "SMC prefix alone must not become validated")
            require(mapping.aggregationRole == .none, "Unvalidated SMC prefix must not aggregate")
        }
        require(catalog.mapping(for: cpuCandidate)?.category == .cpu, "Tp* candidate may retain a provisional category")
        require(catalog.mapping(for: gpuCandidate)?.category == .gpu, "Tg* candidate may retain a provisional category")
        require(catalog.mapping(for: memoryCandidate)?.category == .memory, "Tm* candidate may retain a provisional category")
    }

    private static func testCatalogMatchingIsDeterministic(_ catalog: SensorCatalog) {
        let firstIDs = catalog.entries.map(\.id)
        let secondIDs = SensorCatalog(entries: catalog.entries).entries.map(\.id)
        require(firstIDs == secondIDs, "Catalog ordering must be deterministic")
        require(catalog.entries.count == SensorCatalog.m4Initial.entries.count, "Catalog values must not mutate during matching")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }
}
