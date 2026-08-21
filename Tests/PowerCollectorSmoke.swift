import Foundation

@main
struct PowerCollectorSmoke {
    static func main() {
        let snapshot = PowerCollector().collect()

        if let percent = snapshot.batteryPercent {
            precondition((0...100).contains(percent), "Battery percent must be in range")
        }

        if let watts = snapshot.batteryFlowWatts {
            precondition(watts.isFinite && watts >= 0, "Battery power must be finite and non-negative")
        }

        if let ratedWatts = snapshot.adapterRatedWatts {
            precondition(ratedWatts > 0, "Adapter rated wattage must be positive")
        }

        if let current = snapshot.currentMilliAmps {
            precondition(current.isFinite, "Battery current must be finite")
        }

        if let voltage = snapshot.voltageMilliVolts {
            precondition(voltage.isFinite && voltage > 0, "Battery voltage must be positive")
        }

        print("MemWatch power collector smoke test passed")
        print("source=\(snapshot.source.rawValue) flow=\(snapshot.flow.rawValue) battery=\(snapshot.batteryPercent.map(String.init) ?? "n/a")% watts=\(snapshot.observableWatts.map { String(format: "%.2f", $0) } ?? "n/a") adapterRated=\(snapshot.adapterRatedWatts.map { String(format: "%.0f", $0) } ?? "n/a")")
    }
}
