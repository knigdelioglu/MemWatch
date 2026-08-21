import AppKit
import Darwin
import Foundation

final class SystemDiagnosticsCollector {
    private var previousTotalTicks: UInt64?
    private var previousIdleTicks: UInt64?

    func collect(includeProcesses: Bool) -> SystemDiagnosticsSnapshot {
        SystemDiagnosticsSnapshot(
            timestamp: Date(),
            cpuUsagePercent: collectCPUUsagePercent(),
            thermalState: collectThermalState(),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            topProcesses: includeProcesses ? collectTopProcesses(limit: 8) : []
        )
    }

    func residentMemoryBytes(for pid: Int32) -> UInt64? {
        guard pid > 0 else { return nil }

        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, expectedSize)
        }

        guard result == expectedSize else { return nil }
        return taskInfo.pti_resident_size
    }

    private func collectCPUUsagePercent() -> Double? {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &cpuLoad) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var ticksTuple = cpuLoad.cpu_ticks
        let ticks: [UInt64] = withUnsafePointer(to: &ticksTuple) { pointer in
            pointer.withMemoryRebound(to: UInt32.self, capacity: Int(CPU_STATE_MAX)) { rebound in
                Array(UnsafeBufferPointer(start: rebound, count: Int(CPU_STATE_MAX))).map(UInt64.init)
            }
        }

        guard ticks.count > Int(CPU_STATE_IDLE) else { return nil }

        let totalTicks = ticks.reduce(0, +)
        let idleTicks = ticks[Int(CPU_STATE_IDLE)]

        defer {
            previousTotalTicks = totalTicks
            previousIdleTicks = idleTicks
        }

        guard let previousTotalTicks,
              let previousIdleTicks,
              totalTicks >= previousTotalTicks,
              idleTicks >= previousIdleTicks else {
            return nil
        }

        let totalDelta = totalTicks - previousTotalTicks
        let idleDelta = idleTicks - previousIdleTicks
        guard totalDelta > 0, idleDelta <= totalDelta else { return nil }

        let busyDelta = totalDelta - idleDelta
        return min(100, max(0, Double(busyDelta) / Double(totalDelta) * 100))
    }

    private func collectThermalState() -> ThermalHealthState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }

    private func collectTopProcesses(limit: Int) -> [ProcessMemorySnapshot] {
        NSWorkspace.shared.runningApplications
            .compactMap { application -> ProcessMemorySnapshot? in
                let pid = application.processIdentifier
                guard let residentBytes = residentMemoryBytes(for: pid), residentBytes > 0 else {
                    return nil
                }

                let name = application.localizedName
                    ?? application.bundleURL?.deletingPathExtension().lastPathComponent
                    ?? "PID \(pid)"

                return ProcessMemorySnapshot(
                    pid: pid,
                    name: name,
                    bundleIdentifier: application.bundleIdentifier,
                    residentBytes: residentBytes
                )
            }
            .sorted {
                if $0.residentBytes == $1.residentBytes {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.residentBytes > $1.residentBytes
            }
            .prefix(limit)
            .map { $0 }
    }
}