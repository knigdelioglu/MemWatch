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

// MARK: - User-facing CPU / GPU temperature

extension ThermalSnapshot {
    /// CPU temperature for the UI. Uses the validated canonical aggregate
    /// when one exists; otherwise falls back to the Apple Silicon die
    /// sensors published over IOHID (M1–M3: `pACC/eACC MTR Temp Sensor*`,
    /// M4 and later: `PMU tdie*`). The catalog intentionally keeps these as
    /// context-only, which previously left the CPU value permanently
    /// "unavailable" on Apple Silicon.
    var cpuTemperatureCelsius: Double? {
        if let aggregate = aggregates[.cpu]?.currentCelsius {
            return aggregate
        }
        return dieTemperature(preferredPatterns: [
            "(?i)^[pe]ACC MTR Temp Sensor",
            "(?i)^PMU tdie"
        ])
    }

    /// GPU temperature for the UI with the same fallback strategy
    /// (M1–M3: `GPU MTR Temp Sensor*`, M4 and later: `PMU2 tdie*`).
    var gpuTemperatureCelsius: Double? {
        if let aggregate = aggregates[.gpu]?.currentCelsius {
            return aggregate
        }
        return dieTemperature(preferredPatterns: [
            "(?i)^GPU MTR Temp Sensor",
            "(?i)^PMU2 tdie"
        ])
    }

    /// Average of the valid readings of the first pattern that matches any
    /// sensor in this snapshot's hardware epoch.
    private func dieTemperature(preferredPatterns: [String]) -> Double? {
        let current = readings.filter { $0.hardwareEpoch == hardwareEpoch }
        for pattern in preferredPatterns {
            let values: [Double] = current.compactMap { reading in
                guard let name = reading.identity.rawName,
                      name.range(of: pattern, options: .regularExpression) != nil,
                      let celsius = reading.sample.validCelsius,
                      celsius > 0, celsius < 125 else {
                    return nil
                }
                return celsius
            }
            if !values.isEmpty {
                return values.reduce(0, +) / Double(values.count)
            }
        }
        return nil
    }
}
