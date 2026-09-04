import Foundation

struct TemperatureAggregate: Sendable, Equatable, Hashable {
    let category: TemperatureSensorCategory
    let source: TemperatureSensorSource
    let currentCelsius: Double
    let averageCelsius: Double?
    let hottestCelsius: Double?
    let contributorCatalogIDs: [String]
    let hardwareEpoch: UInt64
    let selectionGeneration: UInt64
}

struct ThermalAggregates: Sendable, Equatable {
    let aggregates: [TemperatureAggregate]

    init(_ aggregates: [TemperatureAggregate] = []) {
        var byCategory: [TemperatureSensorCategory: TemperatureAggregate] = [:]
        for aggregate in aggregates {
            byCategory[aggregate.category] = aggregate
        }
        self.aggregates = TemperatureSensorCategory.allCases.compactMap { byCategory[$0] }
    }

    static let empty = ThermalAggregates()

    func aggregate(for category: TemperatureSensorCategory) -> TemperatureAggregate? {
        aggregates.first { $0.category == category }
    }

    subscript(category: TemperatureSensorCategory) -> TemperatureAggregate? {
        aggregate(for: category)
    }
}

/// Pure category aggregation. It never merges readings from different sources
/// and never derives memory temperature from another category.
struct ThermalAggregator: Sendable {
    func aggregate(
        readings: [TemperatureSensorReading],
        selections: ThermalCategorySourceSelections,
        hardwareEpoch: UInt64
    ) -> ThermalAggregates {
        ThermalAggregates(
            selections.selections.compactMap { selection in
                aggregate(
                    category: selection.category,
                    readings: readings,
                    selection: selection,
                    hardwareEpoch: hardwareEpoch
                )
            }
        )
    }

    func aggregate(
        category: TemperatureSensorCategory,
        readings: [TemperatureSensorReading],
        selection: TemperatureCategorySourceSelection,
        hardwareEpoch: UInt64
    ) -> TemperatureAggregate? {
        guard selection.category == category,
              let source = selection.source else {
            return nil
        }

        let eligibleReadings = readings.filter { reading in
            guard reading.identity.source == source,
                  reading.mapping.category == category,
                  reading.mapping.status == .mapped,
                  reading.hardwareEpoch == hardwareEpoch,
                  let celsius = reading.sample.validCelsius,
                  TemperatureValidator.isValid(celsius) else {
                return false
            }

            if selection.catalogEntryIDs.isEmpty {
                return true
            }
            guard let catalogID = reading.mapping.catalogID else { return false }
            return selection.catalogEntryIDs.contains(catalogID)
        }

        switch category {
        case .cpu:
            return aggregateCompute(
                category: .cpu,
                source: source,
                readings: eligibleReadings,
                packageRole: .cpuPackage,
                clusterRole: .cpuClusterMember,
                selectionGeneration: selection.selectionGeneration,
                hardwareEpoch: hardwareEpoch
            )
        case .gpu:
            return aggregateCompute(
                category: .gpu,
                source: source,
                readings: eligibleReadings,
                packageRole: .gpuPackage,
                clusterRole: .gpuClusterMember,
                selectionGeneration: selection.selectionGeneration,
                hardwareEpoch: hardwareEpoch
            )
        case .battery:
            return aggregateCanonicalSingle(
                category: .battery,
                source: source,
                readings: eligibleReadings.filter {
                    $0.mapping.aggregationRole == .canonicalBattery
                        && $0.mapping.confidence >= .high
                },
                selectionGeneration: selection.selectionGeneration,
                hardwareEpoch: hardwareEpoch
            )
        case .storage:
            return aggregateCanonicalSingle(
                category: .storage,
                source: source,
                readings: eligibleReadings.filter {
                    $0.mapping.aggregationRole == .canonicalStorage
                        && $0.mapping.confidence >= .high
                },
                selectionGeneration: selection.selectionGeneration,
                hardwareEpoch: hardwareEpoch
            )
        case .memory, .soc, .memoryController, .pmu, .ambient, .enclosure, .unknown:
            // Phase 1 deliberately has no validated memory/SoC aggregate and
            // no user-facing aggregate for context-only categories.
            return nil
        }
    }

    private func aggregateCompute(
        category: TemperatureSensorCategory,
        source: TemperatureSensorSource,
        readings: [TemperatureSensorReading],
        packageRole: TemperatureAggregationRole,
        clusterRole: TemperatureAggregationRole,
        selectionGeneration: UInt64,
        hardwareEpoch: UInt64
    ) -> TemperatureAggregate? {
        let validatedReadings = readings.filter { $0.mapping.confidence == .validated }

        // A package is canonical. Cluster members are never added to it.
        if let package = validatedReadings
            .filter({ $0.mapping.aggregationRole == packageRole })
            .sorted(by: stableReadingOrder)
            .first,
           let celsius = package.sample.validCelsius {
            return TemperatureAggregate(
                category: category,
                source: source,
                currentCelsius: celsius,
                averageCelsius: celsius,
                hottestCelsius: celsius,
                contributorCatalogIDs: contributorIDs(for: [package]),
                hardwareEpoch: hardwareEpoch,
                selectionGeneration: selectionGeneration
            )
        }

        let clusterMembers = validatedReadings.filter {
            $0.mapping.aggregationRole == clusterRole
                && $0.mapping.aggregationGroup != nil
        }
        let groups = Dictionary(grouping: clusterMembers) {
            $0.mapping.aggregationGroup ?? ""
        }
        guard let selectedGroup = groups
            .filter({ !$0.key.isEmpty })
            .sorted(by: stableGroupOrder)
            .first?.value,
              !selectedGroup.isEmpty else {
            return nil
        }

        let values = selectedGroup.compactMap(\.sample.validCelsius)
        guard !values.isEmpty,
              let hottest = values.max() else {
            return nil
        }
        let average = values.reduce(0, +) / Double(values.count)

        return TemperatureAggregate(
            category: category,
            source: source,
            currentCelsius: hottest,
            averageCelsius: average,
            hottestCelsius: hottest,
            contributorCatalogIDs: contributorIDs(for: selectedGroup),
            hardwareEpoch: hardwareEpoch,
            selectionGeneration: selectionGeneration
        )
    }

    private func aggregateCanonicalSingle(
        category: TemperatureSensorCategory,
        source: TemperatureSensorSource,
        readings: [TemperatureSensorReading],
        selectionGeneration: UInt64,
        hardwareEpoch: UInt64
    ) -> TemperatureAggregate? {
        guard let reading = readings.sorted(by: stableReadingOrder).first,
              let celsius = reading.sample.validCelsius else {
            return nil
        }

        return TemperatureAggregate(
            category: category,
            source: source,
            currentCelsius: celsius,
            averageCelsius: nil,
            hottestCelsius: nil,
            contributorCatalogIDs: contributorIDs(for: [reading]),
            hardwareEpoch: hardwareEpoch,
            selectionGeneration: selectionGeneration
        )
    }

    private func stableReadingOrder(
        lhs: TemperatureSensorReading,
        rhs: TemperatureSensorReading
    ) -> Bool {
        let lhsID = lhs.mapping.catalogID ?? lhs.identity.rawIdentifier
        let rhsID = rhs.mapping.catalogID ?? rhs.identity.rawIdentifier
        if lhsID != rhsID { return lhsID < rhsID }
        return lhs.identity.rawIdentifier < rhs.identity.rawIdentifier
    }

    private func stableGroupOrder(
        lhs: (key: String, value: [TemperatureSensorReading]),
        rhs: (key: String, value: [TemperatureSensorReading])
    ) -> Bool {
        if lhs.value.count != rhs.value.count {
            return lhs.value.count > rhs.value.count
        }
        return lhs.key < rhs.key
    }

    private func contributorIDs(for readings: [TemperatureSensorReading]) -> [String] {
        Array(
            Set(readings.map { $0.mapping.catalogID ?? $0.identity.rawIdentifier })
        ).sorted()
    }
}
