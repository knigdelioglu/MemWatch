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

    /// Primary process-memory metric. This is the metric closest to the
    /// per-process value shown by Activity Monitor.
    func physicalFootprintBytes(for pid: Int32) -> UInt64? {
        guard pid > 0 else { return nil }

        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, pointer)
        }

        guard result == 0, usage.ri_phys_footprint > 0 else { return nil }
        return usage.ri_phys_footprint
    }

    /// RSS is retained only as the documented fallback for processes for
    /// which proc_pid_rusage is unavailable or denied.
    func residentFallbackBytes(for pid: Int32) -> UInt64? {
        guard pid > 0,
              let info = taskAllInfo(for: pid),
              info.ptinfo.pti_resident_size > 0 else {
            return nil
        }
        return info.ptinfo.pti_resident_size
    }

    func processMemoryMeasurement(for pid: Int32) -> ProcessMemoryMeasurement? {
        ProcessMemoryMeasurementResolver.resolve(
            physicalFootprintBytes: physicalFootprintBytes(for: pid),
            residentFallbackBytes: residentFallbackBytes(for: pid)
        )
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

    private struct RunningApplicationRecord {
        let metadata: ProcessApplicationMetadata
        let isApplicationRoot: Bool
    }

    private func collectTopProcesses(limit: Int) -> [ProcessMemorySnapshot] {
        let records = collectRunningApplications()

        var metadataByPID: [Int32: ProcessApplicationMetadata] = [:]
        for record in records where metadataByPID[record.metadata.pid] == nil {
            metadataByPID[record.metadata.pid] = record.metadata
        }

        let applicationRoots = records
            .filter(\.isApplicationRoot)
            .map(\.metadata)

        let inventory = collectProcessInventory(metadataByPID: metadataByPID)
        return ProcessMemoryAggregator.aggregate(
            inventory: inventory,
            applications: applicationRoots,
            limit: limit
        ).snapshots
    }

    private func collectRunningApplications() -> [RunningApplicationRecord] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard !application.isTerminated else { return nil }

            let pid = application.processIdentifier
            guard pid > 0 else { return nil }

            let executablePath = application.executableURL?.standardizedFileURL.path
            let bundlePath = application.bundleURL?.standardizedFileURL.path
            let fallbackName = executablePath.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
            }
            let name = application.localizedName
                ?? fallbackName
                ?? "PID \(pid)"

            return RunningApplicationRecord(
                metadata: ProcessApplicationMetadata(
                    pid: pid,
                    name: name,
                    bundleIdentifier: application.bundleIdentifier,
                    bundlePath: bundlePath,
                    executablePath: executablePath
                ),
                isApplicationRoot: application.activationPolicy != .prohibited
            )
        }
    }

    private func collectProcessInventory(
        metadataByPID: [Int32: ProcessApplicationMetadata]
    ) -> [ProcessInventoryEntry] {
        allPIDs().compactMap { pid in
            guard let info = taskAllInfo(for: pid) else { return nil }

            let application = metadataByPID[pid]
            let executablePath = processPath(for: pid) ?? application?.executablePath
            let name = application?.name
                ?? processName(for: pid)
                ?? executablePath.map {
                    URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
                }
                ?? "PID \(pid)"

            // The task-all-info call already supplies RSS for the fallback
            // path, so only the primary footprint API is repeated per PID.
            let measurement = ProcessMemoryMeasurementResolver.resolve(
                physicalFootprintBytes: physicalFootprintBytes(for: pid),
                residentFallbackBytes: info.ptinfo.pti_resident_size
            )
            guard let measurement else { return nil }

            return ProcessInventoryEntry(
                pid: pid,
                parentPID: Int32(info.pbsd.pbi_ppid),
                name: name,
                executablePath: executablePath,
                bundleIdentifier: application?.bundleIdentifier,
                memoryBytes: measurement.bytes,
                memoryMetric: measurement.metric
            )
        }
    }

    private func taskAllInfo(for pid: Int32) -> proc_taskallinfo? {
        guard pid > 0 else { return nil }

        var info = proc_taskallinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskallinfo>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, pointer, expectedSize)
        }

        guard result == expectedSize else { return nil }
        return info
    }

    private func allPIDs() -> [Int32] {
        let reportedBytes = proc_listpids(PROC_ALL_PIDS, 0, nil, 0)
        guard reportedBytes > 0 else { return [] }

        let pidStride = MemoryLayout<pid_t>.stride
        let maximumProcessCount = 16_384
        var capacity = min(
            maximumProcessCount,
            max(Int(reportedBytes) / pidStride + 64, 256)
        )

        for _ in 0..<2 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let bufferSize = Int32(clamping: pids.count * pidStride)
            let returnedBytes = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(
                    PROC_ALL_PIDS,
                    0,
                    buffer.baseAddress,
                    bufferSize
                )
            }

            guard returnedBytes > 0 else { return [] }
            let returnedCount = min(
                Int(returnedBytes) / pidStride,
                pids.count
            )
            let result = pids.prefix(returnedCount)
                .map { Int32($0) }
                .filter { $0 > 0 }

            if Int(returnedBytes) < pids.count * pidStride || capacity == maximumProcessCount {
                return result
            }

            capacity = min(capacity * 2, maximumProcessCount)
        }

        return []
    }

    private func processName(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let bufferSize = UInt32(buffer.count)
        let length = buffer.withUnsafeMutableBytes { rawBuffer in
            proc_name(pid, rawBuffer.baseAddress, bufferSize)
        }

        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private func processPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let bufferSize = UInt32(buffer.count)
        let length = buffer.withUnsafeMutableBytes { rawBuffer in
            proc_pidpath(pid, rawBuffer.baseAddress, bufferSize)
        }

        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
