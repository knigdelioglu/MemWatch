import Foundation

@main
struct ThermalSourcePolicyTests {
    private static let policy = ThermalSourcePolicy()

    static func main() {
        testConfidenceBeatsLowerConfidence()
        testPriorityBreaksEqualConfidence()
        testOneSourcePerCategory()
        testDifferentCategoriesMayMixSources()
        testTemperatureSimilarityIsIrrelevant()
        testBetterAlternateBeatsHealthyCurrent()
        testEqualQualityRetainsHealthyCurrent()
        testUnavailableBackendProducesNoSelection()
        print("PASS Thermal source policy")
    }

    private static func testConfidenceBeatsLowerConfidence() {
        let entries = [
            entry(id: "hid-storage", source: .ioHID, category: .storage, confidence: .high, priority: 100, role: .canonicalStorage),
            entry(id: "smc-storage", source: .appleSMC, category: .storage, confidence: .low, priority: 999, role: .canonicalStorage)
        ]
        let result = evaluate(entries: entries)
        require(result.selections[.storage]?.source == .ioHID, "Semantic confidence must beat explicit priority from a weaker source")
    }

    private static func testPriorityBreaksEqualConfidence() {
        let entries = [
            entry(id: "hid-battery", source: .ioHID, category: .battery, confidence: .high, priority: 20, role: .canonicalBattery),
            entry(id: "smc-battery", source: .appleSMC, category: .battery, confidence: .high, priority: 10, role: .canonicalBattery)
        ]
        let result = evaluate(entries: entries)
        require(result.selections[.battery]?.source == .ioHID, "Explicit priority must break equal semantic confidence")
        require(result.selections[.battery]?.reason == .selectedByExplicitPriority, "Priority decision reason must be explicit")
    }

    private static func testOneSourcePerCategory() {
        let entries = [
            entry(id: "hid-storage", source: .ioHID, category: .storage, confidence: .high, priority: 10, role: .canonicalStorage),
            entry(id: "smc-storage", source: .appleSMC, category: .storage, confidence: .high, priority: 5, role: .canonicalStorage)
        ]
        let result = evaluate(entries: entries)
        let storage = result.selections[.storage]
        require(storage?.source == .ioHID, "A category must have one canonical source")
        require(storage?.catalogEntryIDs == ["hid-storage"], "Cross-backend catalog entries must not be merged")
    }

    private static func testDifferentCategoriesMayMixSources() {
        let entries = [
            entry(id: "hid-storage", source: .ioHID, category: .storage, confidence: .high, priority: 10, role: .canonicalStorage),
            entry(id: "smc-cpu", source: .appleSMC, category: .cpu, confidence: .validated, priority: 10, role: .cpuPackage)
        ]
        let result = evaluate(entries: entries)
        require(result.selections[.storage]?.source == .ioHID, "Storage may select HID")
        require(result.selections[.cpu]?.source == .appleSMC, "CPU may independently select AppleSMC")
    }

    private static func testTemperatureSimilarityIsIrrelevant() {
        let entries = [
            entry(id: "hid-storage", source: .ioHID, category: .storage, confidence: .high, priority: 10, role: .canonicalStorage),
            entry(id: "smc-storage", source: .appleSMC, category: .storage, confidence: .low, priority: 5, role: .canonicalStorage)
        ]
        let first = evaluate(entries: entries)
        let second = evaluate(entries: entries, generation: first.selectionGeneration)
        require(first.selections[.storage]?.source == second.selections[.storage]?.source, "Selection must not inspect measured temperature values")
    }

    private static func testBetterAlternateBeatsHealthyCurrent() {
        let hid = entry(id: "hid-cpu", source: .ioHID, category: .cpu, confidence: .medium, priority: 10, role: .cpuPackage)
        let smc = entry(id: "smc-cpu", source: .appleSMC, category: .cpu, confidence: .validated, priority: 1, role: .cpuPackage)
        let first = evaluate(entries: [hid])
        let second = evaluate(
            entries: [hid, smc],
            current: first.selections,
            generation: first.selectionGeneration
        )
        require(second.selections[.cpu]?.source == .appleSMC, "A validated alternate must beat a healthy medium source")
        require(second.selections[.cpu]?.reason == .selectedBySemanticConfidence, "Confidence upgrade must explain source change")
        require(second.selectionGeneration > first.selectionGeneration, "Source change must advance selection generation")
    }

    private static func testEqualQualityRetainsHealthyCurrent() {
        let hid = entry(id: "hid-storage", source: .ioHID, category: .storage, confidence: .high, priority: 10, role: .canonicalStorage)
        let smc = entry(id: "smc-storage", source: .appleSMC, category: .storage, confidence: .high, priority: 10, role: .canonicalStorage)
        let first = evaluate(entries: [hid, smc])
        let expectedFirstSource = first.selections[.storage]?.source
        let second = evaluate(
            entries: [hid, smc],
            current: first.selections,
            generation: first.selectionGeneration
        )
        require(second.selections[.storage]?.source == expectedFirstSource, "Equal semantic quality must retain the healthy current source")
        require(second.selections[.storage]?.reason == .retainedCurrentSource, "Stickiness decision reason must be explicit")
        require(!second.didChange, "Retaining a source must not advance generation")
    }

    private static func testUnavailableBackendProducesNoSelection() {
        let entries = [entry(id: "hid-storage", source: .ioHID, category: .storage, confidence: .high, priority: 10, role: .canonicalStorage)]
        let result = evaluate(
            entries: entries,
            statuses: [.ioHID: ThermalTestFixtures.backendStatus(.ioHID, availability: .unavailable(reason: .permissionDenied))]
        )
        require(result.selections[.storage]?.source == nil, "Discovery failure must trigger immediate source fallback")
        require(result.selections[.storage]?.reason == .backendUnavailable, "Backend failure must remain visible in policy output")
    }

    private static func entry(
        id: String,
        source: TemperatureSensorSource,
        category: TemperatureSensorCategory,
        confidence: SensorConfidence,
        priority: Int,
        role: TemperatureAggregationRole
    ) -> SensorCatalogEntry {
        ThermalTestFixtures.catalogEntry(
            id: id,
            source: source,
            category: category,
            confidence: confidence,
            role: role,
            priority: priority
        )
    }

    private static func evaluate(
        entries: [SensorCatalogEntry],
        statuses: ThermalBackendStatuses? = nil,
        current: ThermalCategorySourceSelections = .empty,
        generation: UInt64 = 0
    ) -> ThermalSourcePolicyDecision {
        let resolvedStatuses = statuses ?? [
            .ioHID: ThermalTestFixtures.backendStatus(.ioHID),
            .appleSMC: ThermalTestFixtures.backendStatus(.appleSMC)
        ]
        return policy.evaluate(
            backendStatuses: resolvedStatuses,
            catalogEntries: entries,
            currentSelections: current,
            selectionGeneration: generation
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
