import Foundation

struct ThermalSnapshot: Sendable, Equatable {
    let timestamp: Date
    let hardwareEpoch: UInt64
    let backendStatuses: ThermalBackendStatuses
    let categorySourceSelections: ThermalCategorySourceSelections
    let categoryAvailability: ThermalCategoryAvailabilityReport
    let aggregates: ThermalAggregates
    let readings: [TemperatureSensorReading]

    static let empty = ThermalSnapshot(
        timestamp: .distantPast,
        hardwareEpoch: 0,
        backendStatuses: [:],
        categorySourceSelections: .empty,
        categoryAvailability: .empty,
        aggregates: .empty,
        readings: []
    )

    func accepts(reading: TemperatureSensorReading) -> Bool {
        reading.hardwareEpoch == hardwareEpoch
    }

    func accepts(aggregate: TemperatureAggregate) -> Bool {
        guard aggregate.hardwareEpoch == hardwareEpoch,
              let selection = categorySourceSelections[aggregate.category] else {
            return false
        }
        return selection.source == aggregate.source
            && selection.selectionGeneration == aggregate.selectionGeneration
    }
}
