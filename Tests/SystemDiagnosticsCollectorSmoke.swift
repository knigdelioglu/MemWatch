import Darwin
import Foundation

@main
struct SystemDiagnosticsCollectorSmoke {
    static func main() {
        let collector = SystemDiagnosticsCollector()

        _ = collector.collect(includeProcesses: false)
        usleep(300_000)
        let snapshot = collector.collect(includeProcesses: true)

        if let cpu = snapshot.cpuUsagePercent {
            precondition(cpu >= 0 && cpu <= 100, "CPU usage must be in range")
        } else {
            preconditionFailure("Second CPU sample should produce a delta")
        }

        precondition((0...1).contains(snapshot.thermalState.severity), "Thermal severity must be normalized")

        let ownResident = collector.residentMemoryBytes(for: getpid())
        precondition(ownResident != nil && ownResident! > 0, "Current process resident memory must be readable")

        for process in snapshot.topProcesses {
            precondition(process.pid > 0, "Process PID must be positive")
            precondition(!process.name.isEmpty, "Process name must not be empty")
            precondition(process.residentBytes > 0, "Process resident memory must be positive")
        }

        print("MemWatch system diagnostics collector smoke test passed")
        print("cpu=\(String(format: "%.1f", snapshot.cpuUsagePercent ?? -1))% thermal=\(snapshot.thermalState.rawValue) lowPower=\(snapshot.lowPowerModeEnabled)")
        print("ownResident=\(ownResident ?? 0) topProcesses=\(snapshot.topProcesses.count)")
    }
}