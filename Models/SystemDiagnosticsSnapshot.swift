import Foundation

enum ThermalHealthState: String, Sendable {
    case nominal
    case fair
    case serious
    case critical

    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }

    var severity: Double {
        switch self {
        case .nominal: return 0
        case .fair: return 0.33
        case .serious: return 0.66
        case .critical: return 1
        }
    }
}

enum ProcessMemoryMetric: String, Equatable, Hashable, Sendable {
    case physicalFootprint
    case residentFallback
    case mixed

    var displayName: String {
        switch self {
        case .physicalFootprint: return "Physical footprint"
        case .residentFallback: return "RSS fallback"
        case .mixed: return "Mixed · RSS fallback"
        }
    }
}

struct ProcessMemoryMeasurement: Equatable, Sendable {
    let bytes: UInt64
    let metric: ProcessMemoryMetric
}

enum ProcessMemoryMeasurementResolver {
    static func resolve(
        physicalFootprintBytes: UInt64?,
        residentFallbackBytes: UInt64?
    ) -> ProcessMemoryMeasurement? {
        if let physicalFootprintBytes, physicalFootprintBytes > 0 {
            return ProcessMemoryMeasurement(
                bytes: physicalFootprintBytes,
                metric: .physicalFootprint
            )
        }

        if let residentFallbackBytes, residentFallbackBytes > 0 {
            return ProcessMemoryMeasurement(
                bytes: residentFallbackBytes,
                metric: .residentFallback
            )
        }

        return nil
    }
}

enum ProcessMemoryGroupKind: String, Equatable, Sendable {
    case application
    case standalone

    var symbolName: String {
        switch self {
        case .application: return "app.fill"
        case .standalone: return "terminal.fill"
        }
    }
}

struct ProcessMemorySnapshot: Identifiable, Equatable, Sendable {
    /// For an application group this is the application's root PID. For a
    /// standalone process it is the process PID itself.
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let executablePath: String?
    let memoryBytes: UInt64
    let memoryMetric: ProcessMemoryMetric
    /// Validation-only RSS sum for the same PIDs. The production UI continues
    /// to render `memoryBytes`, which prefers physical footprint.
    let residentBytes: UInt64
    let residentProcessCount: Int
    let physicalFootprintProcessCount: Int
    let residentFallbackProcessCount: Int
    let processIDs: [Int32]
    let groupKind: ProcessMemoryGroupKind

    var id: Int32 { pid }
    var processCount: Int { processIDs.count }
}

/// Immutable process data collected in one inventory pass. The collector
/// never traverses a child tree while aggregating, which lets ownership be
/// assigned once and prevents double-counting.
struct ProcessInventoryEntry: Equatable, Sendable {
    let pid: Int32
    let parentPID: Int32
    let name: String
    let executablePath: String?
    let bundleIdentifier: String?
    let memoryBytes: UInt64
    let memoryMetric: ProcessMemoryMetric
    /// Both native values are retained for validation. `memoryBytes` remains
    /// the single production metric selected by the resolver.
    let physicalFootprintBytes: UInt64?
    let residentBytes: UInt64?

    init(
        pid: Int32,
        parentPID: Int32,
        name: String,
        executablePath: String?,
        bundleIdentifier: String?,
        memoryBytes: UInt64,
        memoryMetric: ProcessMemoryMetric,
        physicalFootprintBytes: UInt64? = nil,
        residentBytes: UInt64? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.memoryBytes = memoryBytes
        self.memoryMetric = memoryMetric
        self.physicalFootprintBytes = physicalFootprintBytes
        self.residentBytes = residentBytes
    }
}

/// Value-only metadata copied from NSRunningApplication before the inventory
/// is handed to the pure grouping layer.
struct ProcessApplicationMetadata: Equatable, Sendable {
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let bundlePath: String?
    let executablePath: String?
}

enum ProcessMemoryGroupOwner: Hashable, Sendable {
    case application(rootPID: Int32)
    case standalone(pid: Int32)
}

struct ProcessMemoryAggregation: Sendable {
    let snapshots: [ProcessMemorySnapshot]
    let ownershipByPID: [Int32: ProcessMemoryGroupOwner]

    /// Counts duplicate PID appearances in the visible grouped rows. This is
    /// a diagnostic invariant; ownership itself is still assigned from the
    /// de-duplicated inventory.
    var duplicateAssignedPIDCount: Int {
        let assignedPIDs = snapshots.flatMap(\.processIDs)
        return assignedPIDs.count - Set(assignedPIDs).count
    }
}

enum ProcessMemoryAggregator {
    static func aggregate(
        inventory: [ProcessInventoryEntry],
        applications: [ProcessApplicationMetadata],
        limit: Int
    ) -> ProcessMemoryAggregation {
        let entries = uniqueInventory(inventory)
        let applications = uniqueApplications(applications)
        let inventoryByPID = Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0) })
        let applicationByPID = Dictionary(uniqueKeysWithValues: applications.map { ($0.pid, $0) })

        var ownershipByPID: [Int32: ProcessMemoryGroupOwner] = [:]
        var applicationEntries: [Int32: [ProcessInventoryEntry]] = [:]
        var standaloneEntries: [ProcessInventoryEntry] = []

        for entry in entries {
            if let rootPID = applicationRoot(
                for: entry,
                inventoryByPID: inventoryByPID,
                applications: applications,
                applicationByPID: applicationByPID
            ) {
                ownershipByPID[entry.pid] = .application(rootPID: rootPID)
                applicationEntries[rootPID, default: []].append(entry)
            } else {
                ownershipByPID[entry.pid] = .standalone(pid: entry.pid)
                standaloneEntries.append(entry)
            }
        }

        var snapshots: [ProcessMemorySnapshot] = []

        for (rootPID, entries) in applicationEntries {
            let metadata = applicationByPID[rootPID]
            snapshots.append(
                makeApplicationSnapshot(
                    rootPID: rootPID,
                    entries: entries,
                    metadata: metadata
                )
            )
        }

        snapshots.append(contentsOf: standaloneEntries.map(makeStandaloneSnapshot))
        snapshots.sort(by: sortSnapshots)

        let boundedLimit = max(limit, 0)
        if snapshots.count > boundedLimit {
            snapshots.removeLast(snapshots.count - boundedLimit)
        }

        return ProcessMemoryAggregation(
            snapshots: snapshots,
            ownershipByPID: ownershipByPID
        )
    }

    private static func uniqueInventory(_ inventory: [ProcessInventoryEntry]) -> [ProcessInventoryEntry] {
        var entriesByPID: [Int32: ProcessInventoryEntry] = [:]
        for entry in inventory.sorted(by: { $0.pid < $1.pid }) {
            if entriesByPID[entry.pid] == nil {
                entriesByPID[entry.pid] = entry
            }
        }
        return entriesByPID.values.sorted(by: { $0.pid < $1.pid })
    }

    private static func uniqueApplications(
        _ applications: [ProcessApplicationMetadata]
    ) -> [ProcessApplicationMetadata] {
        var applicationsByPID: [Int32: ProcessApplicationMetadata] = [:]
        for application in applications.sorted(by: { $0.pid < $1.pid }) {
            if applicationsByPID[application.pid] == nil {
                applicationsByPID[application.pid] = application
            }
        }
        return applicationsByPID.values.sorted(by: { $0.pid < $1.pid })
    }

    private static func applicationRoot(
        for entry: ProcessInventoryEntry,
        inventoryByPID: [Int32: ProcessInventoryEntry],
        applications: [ProcessApplicationMetadata],
        applicationByPID: [Int32: ProcessApplicationMetadata]
    ) -> Int32? {
        if applicationByPID[entry.pid] != nil {
            return entry.pid
        }

        var currentPID = entry.pid
        var visited: Set<Int32> = []
        visited.insert(currentPID)

        while let current = inventoryByPID[currentPID] {
            let parentPID = current.parentPID
            guard parentPID > 0,
                  parentPID != currentPID,
                  visited.insert(parentPID).inserted else {
                break
            }

            if applicationByPID[parentPID] != nil {
                return parentPID
            }

            currentPID = parentPID
        }

        // A renderer/helper can be reparented after its app changes state.
        // Path and bundle metadata are used only when there is one
        // deterministic candidate; ambiguous matches stay standalone.
        let pathCandidates = applications.filter {
            pathBelongsToApplication(entry.executablePath, application: $0)
        }
        if pathCandidates.count == 1 {
            return pathCandidates[0].pid
        }

        guard let bundleIdentifier = entry.bundleIdentifier else { return nil }
        let bundleCandidates = applications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }
        return bundleCandidates.count == 1 ? bundleCandidates[0].pid : nil
    }

    private static func pathBelongsToApplication(
        _ processPath: String?,
        application: ProcessApplicationMetadata
    ) -> Bool {
        guard let processPath,
              !processPath.isEmpty else { return false }

        let standardizedProcessPath = standardizedPath(processPath)
        if let executablePath = application.executablePath,
           standardizedProcessPath == standardizedPath(executablePath) {
            return true
        }

        guard let bundlePath = application.bundlePath,
              !bundlePath.isEmpty else { return false }

        let bundlePrefix = standardizedPath(bundlePath).hasSuffix("/")
            ? standardizedPath(bundlePath)
            : standardizedPath(bundlePath) + "/"
        return standardizedProcessPath.hasPrefix(bundlePrefix)
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func makeApplicationSnapshot(
        rootPID: Int32,
        entries: [ProcessInventoryEntry],
        metadata: ProcessApplicationMetadata?
    ) -> ProcessMemorySnapshot {
        let sortedEntries = entries.sorted(by: { $0.pid < $1.pid })
        let name = metadata?.name
            ?? sortedEntries.first?.name
            ?? "PID \(rootPID)"

        return ProcessMemorySnapshot(
            pid: rootPID,
            name: name,
            bundleIdentifier: metadata?.bundleIdentifier,
            executablePath: metadata?.executablePath,
            memoryBytes: saturatingSum(sortedEntries.map(\.memoryBytes)),
            memoryMetric: aggregateMetric(sortedEntries),
            residentBytes: saturatingSum(sortedEntries.compactMap(\.residentBytes)),
            residentProcessCount: sortedEntries.reduce(into: 0) { count, entry in
                if let residentBytes = entry.residentBytes, residentBytes > 0 {
                    count += 1
                }
            },
            physicalFootprintProcessCount: sortedEntries.reduce(into: 0) { count, entry in
                if entry.memoryMetric == .physicalFootprint {
                    count += 1
                }
            },
            residentFallbackProcessCount: sortedEntries.reduce(into: 0) { count, entry in
                if entry.memoryMetric == .residentFallback {
                    count += 1
                }
            },
            processIDs: sortedEntries.map(\.pid),
            groupKind: .application
        )
    }

    private static func makeStandaloneSnapshot(
        _ entry: ProcessInventoryEntry
    ) -> ProcessMemorySnapshot {
        ProcessMemorySnapshot(
            pid: entry.pid,
            name: entry.name,
            bundleIdentifier: entry.bundleIdentifier,
            executablePath: entry.executablePath,
            memoryBytes: entry.memoryBytes,
            memoryMetric: entry.memoryMetric,
            residentBytes: entry.residentBytes ?? 0,
            residentProcessCount: entry.residentBytes.map { $0 > 0 ? 1 : 0 } ?? 0,
            physicalFootprintProcessCount: entry.memoryMetric == .physicalFootprint ? 1 : 0,
            residentFallbackProcessCount: entry.memoryMetric == .residentFallback ? 1 : 0,
            processIDs: [entry.pid],
            groupKind: .standalone
        )
    }

    private static func aggregateMetric(
        _ entries: [ProcessInventoryEntry]
    ) -> ProcessMemoryMetric {
        let metrics = Set(entries.map(\.memoryMetric))
        if metrics == Set([ProcessMemoryMetric.physicalFootprint]) {
            return .physicalFootprint
        }
        if metrics == Set([ProcessMemoryMetric.residentFallback]) {
            return .residentFallback
        }
        return .mixed
    }

    private static func sortSnapshots(
        _ lhs: ProcessMemorySnapshot,
        _ rhs: ProcessMemorySnapshot
    ) -> Bool {
        if lhs.memoryBytes == rhs.memoryBytes {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.memoryBytes > rhs.memoryBytes
    }

    private static func saturatingSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
    }
}

struct SystemDiagnosticsSnapshot: Equatable, Sendable {
    let timestamp: Date
    let cpuUsagePercent: Double?
    let thermalState: ThermalHealthState
    let lowPowerModeEnabled: Bool
    let topProcesses: [ProcessMemorySnapshot]

    static let empty = SystemDiagnosticsSnapshot(
        timestamp: .distantPast,
        cpuUsagePercent: nil,
        thermalState: .nominal,
        lowPowerModeEnabled: false,
        topProcesses: []
    )
}

struct SystemHistoryPoint: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let cpuUsagePercent: Double
    let memoryUsagePercent: Double
    let thermalSeverity: Double

    var id: Date { timestamp }
}

enum LaunchAtLoginState: String, Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case needsSetup
    case unavailable

    var displayName: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .requiresApproval: return "Needs approval"
        case .needsSetup: return "Needs setup"
        case .unavailable: return "Unavailable"
        }
    }
}
