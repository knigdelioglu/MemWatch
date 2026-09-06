import AppKit
import Darwin
import Foundation

struct ProcessMemoryCollectionDiagnostics: Sendable {
    let aggregation: ProcessMemoryAggregation
    let inventory: [ProcessInventoryEntry]
    let unavailablePIDs: [Int32]
    let applicationRoots: [ProcessApplicationMetadata]
    let inventoryPIDCount: Int
    let inventoryDuration: TimeInterval
    let groupingDuration: TimeInterval
    let totalDuration: TimeInterval
}

struct SystemDiagnosticsCollection: Sendable {
    let snapshot: SystemDiagnosticsSnapshot
    let processMemory: ProcessMemoryCollectionDiagnostics?
    let totalDuration: TimeInterval
}

final class SystemDiagnosticsCollector {
    private var previousTotalTicks: UInt64?
    private var previousIdleTicks: UInt64?

    func collect(includeProcesses: Bool) -> SystemDiagnosticsSnapshot {
        collectWithDiagnostics(includeProcesses: includeProcesses).snapshot
    }

    func collectWithDiagnostics(
        includeProcesses: Bool,
        processLimit: Int = 8
    ) -> SystemDiagnosticsCollection {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let processMemory = includeProcesses
            ? collectProcessMemoryDiagnostics(limit: processLimit)
            : nil
        let snapshot = SystemDiagnosticsSnapshot(
            timestamp: Date(),
            cpuUsagePercent: collectCPUUsagePercent(),
            thermalState: collectThermalState(),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            topProcesses: processMemory?.aggregation.snapshots ?? []
        )

        return SystemDiagnosticsCollection(
            snapshot: snapshot,
            processMemory: processMemory,
            totalDuration: ProcessInfo.processInfo.systemUptime - startedAt
        )
    }

    /// Primary process-memory metric. This is the metric closest to the
    /// per-process value shown by Activity Monitor.
    func physicalFootprintBytes(for pid: Int32) -> UInt64? {
        guard pid > 0 else { return nil }

        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPointer)
            }
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

    private func collectProcessMemoryDiagnostics(
        limit: Int
    ) -> ProcessMemoryCollectionDiagnostics {
        let totalStartedAt = ProcessInfo.processInfo.systemUptime
        let records = collectRunningApplications()

        var metadataByPID: [Int32: ProcessApplicationMetadata] = [:]
        for record in records where metadataByPID[record.metadata.pid] == nil {
            metadataByPID[record.metadata.pid] = record.metadata
        }

        let explicitApplicationRoots = records
            .filter(\.isApplicationRoot)
            .map(\.metadata)

        let inventoryStartedAt = ProcessInfo.processInfo.systemUptime
        let pids = allPIDs()
        let inventoryResult = collectProcessInventory(
            pids: pids,
            metadataByPID: metadataByPID
        )
        let inventoryDuration = ProcessInfo.processInfo.systemUptime - inventoryStartedAt

        let applicationRoots = mergeApplicationRoots(
            explicit: explicitApplicationRoots,
            inferred: inferredApplicationRoots(from: inventoryResult.entries)
        )

        let groupingStartedAt = ProcessInfo.processInfo.systemUptime
        let aggregation = ProcessMemoryAggregator.aggregate(
            inventory: inventoryResult.entries,
            applications: applicationRoots,
            limit: limit
        )
        let groupingDuration = ProcessInfo.processInfo.systemUptime - groupingStartedAt

        return ProcessMemoryCollectionDiagnostics(
            aggregation: aggregation,
            inventory: inventoryResult.entries,
            unavailablePIDs: inventoryResult.unavailablePIDs,
            applicationRoots: applicationRoots,
            inventoryPIDCount: pids.count,
            inventoryDuration: inventoryDuration,
            groupingDuration: groupingDuration,
            totalDuration: ProcessInfo.processInfo.systemUptime - totalStartedAt
        )
    }

    /// Direct `MemWatch --memory-diagnostics` launches do not always have a
    /// LaunchServices/WindowServer connection, so NSWorkspace can return no
    /// running applications. Exact `.app` path metadata is a conservative
    /// fallback: only a unique executable directly under an app's
    /// `Contents/MacOS` is allowed to define a root.
    private func inferredApplicationRoots(
        from entries: [ProcessInventoryEntry]
    ) -> [ProcessApplicationMetadata] {
        var candidatesByBundlePath: [String: [ProcessInventoryEntry]] = [:]

        for entry in entries {
            guard let executablePath = entry.executablePath,
                  let bundlePath = applicationBundlePath(for: executablePath),
                  isDirectBundleExecutable(executablePath, bundlePath: bundlePath) else {
                continue
            }
            candidatesByBundlePath[bundlePath, default: []].append(entry)
        }

        return candidatesByBundlePath.compactMap { bundlePath, candidates in
            let uniquePIDs = Set(candidates.map(\.pid))
            guard uniquePIDs.count == 1,
                  let entry = candidates.first else {
                return nil
            }

            let bundle = Bundle(path: bundlePath)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? entry.name

            return ProcessApplicationMetadata(
                pid: entry.pid,
                name: name,
                bundleIdentifier: bundle?.bundleIdentifier ?? entry.bundleIdentifier,
                bundlePath: bundlePath,
                executablePath: entry.executablePath
            )
        }
        .sorted(by: { $0.pid < $1.pid })
    }

    private func mergeApplicationRoots(
        explicit: [ProcessApplicationMetadata],
        inferred: [ProcessApplicationMetadata]
    ) -> [ProcessApplicationMetadata] {
        var rootsByPID: [Int32: ProcessApplicationMetadata] = [:]
        for root in explicit where rootsByPID[root.pid] == nil {
            rootsByPID[root.pid] = root
        }
        let explicitBundlePaths = Set(
            explicit.compactMap { $0.bundlePath }.map(standardizedPath)
        )

        for root in inferred where rootsByPID[root.pid] == nil {
            if let bundlePath = root.bundlePath,
               explicitBundlePaths.contains(standardizedPath(bundlePath)) {
                continue
            }
            rootsByPID[root.pid] = root
        }

        return rootsByPID.values.sorted(by: { $0.pid < $1.pid })
    }

    private func applicationBundlePath(for processPath: String) -> String? {
        let components = URL(fileURLWithPath: standardizedPath(processPath)).pathComponents
        var currentPath = "/"

        for component in components.dropFirst() {
            currentPath = URL(fileURLWithPath: currentPath)
                .appendingPathComponent(component)
                .path
            if component.lowercased().hasSuffix(".app") {
                return standardizedPath(currentPath)
            }
        }

        return nil
    }

    private func isDirectBundleExecutable(
        _ processPath: String,
        bundlePath: String
    ) -> Bool {
        let prefix = standardizedPath(bundlePath).hasSuffix("/")
            ? standardizedPath(bundlePath) + "Contents/MacOS/"
            : standardizedPath(bundlePath) + "/Contents/MacOS/"
        let standardizedProcessPath = standardizedPath(processPath)
        guard standardizedProcessPath.hasPrefix(prefix) else { return false }

        let executableName = String(standardizedProcessPath.dropFirst(prefix.count))
        return !executableName.isEmpty && !executableName.contains("/")
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private struct ProcessInventoryResult {
        let entries: [ProcessInventoryEntry]
        let unavailablePIDs: [Int32]
    }

    private func collectProcessInventory(
        pids: [Int32],
        metadataByPID: [Int32: ProcessApplicationMetadata]
    ) -> ProcessInventoryResult {
        var entries: [ProcessInventoryEntry] = []
        entries.reserveCapacity(pids.count)
        var unavailablePIDs: [Int32] = []

        for pid in pids {
            guard let info = taskAllInfo(for: pid) else {
                unavailablePIDs.append(pid)
                continue
            }

            let application = metadataByPID[pid]
            let executablePath = processPath(for: pid) ?? application?.executablePath
            let name = application?.name
                ?? processName(for: pid)
                ?? executablePath.map {
                    URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
                }
                ?? "PID \(pid)"

            // Read both native values for validation, then let the resolver
            // choose the sole production metric used by the UI.
            let physicalFootprint = physicalFootprintBytes(for: pid)
            let residentBytes = info.ptinfo.pti_resident_size > 0
                ? info.ptinfo.pti_resident_size
                : nil
            guard let measurement = ProcessMemoryMeasurementResolver.resolve(
                physicalFootprintBytes: physicalFootprint,
                residentFallbackBytes: residentBytes
            ) else {
                unavailablePIDs.append(pid)
                continue
            }

            entries.append(
                ProcessInventoryEntry(
                    pid: pid,
                    parentPID: Int32(info.pbsd.pbi_ppid),
                    name: name,
                    executablePath: executablePath,
                    bundleIdentifier: application?.bundleIdentifier,
                    memoryBytes: measurement.bytes,
                    memoryMetric: measurement.metric,
                    physicalFootprintBytes: physicalFootprint,
                    residentBytes: residentBytes
                )
            )
        }

        return ProcessInventoryResult(
            entries: entries,
            unavailablePIDs: unavailablePIDs
        )
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
        let processType = UInt32(bitPattern: PROC_ALL_PIDS)
        let reportedBytes = proc_listpids(processType, 0, nil, 0)
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
                    processType,
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
