import Darwin
import Foundation

@main
struct SystemDiagnosticsCollectorSmoke {
    static func main() {
        processMetricFallbacksAreExplicit()
        groupingAssignsEachPIDOnce()

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
        precondition(!snapshot.topProcesses.isEmpty, "PID inventory should return at least one accessible process")

        let ownFootprint = collector.physicalFootprintBytes(for: getpid())
        precondition(
            ownFootprint != nil && ownFootprint! > 0,
            "Current process physical footprint must be readable"
        )

        let ownMeasurement = collector.processMemoryMeasurement(for: getpid())
        precondition(ownMeasurement != nil && ownMeasurement!.bytes > 0, "Current process memory must be readable")
        precondition(
            ownMeasurement!.metric == .physicalFootprint || ownMeasurement!.metric == .residentFallback,
            "Current process memory source must be explicit"
        )

        for process in snapshot.topProcesses {
            precondition(process.pid > 0, "Process PID must be positive")
            precondition(!process.name.isEmpty, "Process name must not be empty")
            precondition(process.memoryBytes > 0, "Process memory must be positive")
            precondition(!process.processIDs.isEmpty, "Every process row must own at least one PID")
        }

        print("MemWatch system diagnostics collector smoke test passed")
        print("cpu=\(String(format: "%.1f", snapshot.cpuUsagePercent ?? -1))% thermal=\(snapshot.thermalState.rawValue) lowPower=\(snapshot.lowPowerModeEnabled)")
        print("ownFootprint=\(ownFootprint ?? 0) topProcesses=\(snapshot.topProcesses.count)")
    }

    private static func processMetricFallbacksAreExplicit() {
        let footprint = ProcessMemoryMeasurementResolver.resolve(
            physicalFootprintBytes: 300,
            residentFallbackBytes: 500
        )
        precondition(footprint?.bytes == 300, "Physical footprint must be preferred over RSS")
        precondition(footprint?.metric == .physicalFootprint, "Physical footprint source must be labeled")

        let fallback = ProcessMemoryMeasurementResolver.resolve(
            physicalFootprintBytes: nil,
            residentFallbackBytes: 500
        )
        precondition(fallback?.bytes == 500, "RSS must be used when footprint is unavailable")
        precondition(fallback?.metric == .residentFallback, "RSS fallback must be labeled")

        let unavailable = ProcessMemoryMeasurementResolver.resolve(
            physicalFootprintBytes: nil,
            residentFallbackBytes: nil
        )
        precondition(unavailable == nil, "A process with no readable metric must be omitted")
    }

    private static func groupingAssignsEachPIDOnce() {
        let chrome = ProcessApplicationMetadata(
            pid: 100,
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            bundlePath: "/Applications/Google Chrome.app",
            executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        )

        let chromeBundle = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers"
        let inventory = [
            ProcessInventoryEntry(
                pid: 100,
                parentPID: 1,
                name: "Google Chrome",
                executablePath: chrome.executablePath,
                bundleIdentifier: chrome.bundleIdentifier,
                memoryBytes: 100,
                memoryMetric: .physicalFootprint,
                physicalFootprintBytes: 100,
                residentBytes: 50
            ),
            ProcessInventoryEntry(
                pid: 101,
                parentPID: 100,
                name: "Google Chrome Helper",
                executablePath: "\(chromeBundle)/Google Chrome Helper",
                bundleIdentifier: nil,
                memoryBytes: 200,
                memoryMetric: .physicalFootprint,
                physicalFootprintBytes: 200,
                residentBytes: 100
            ),
            ProcessInventoryEntry(
                pid: 102,
                parentPID: 999,
                name: "Google Chrome Helper (Renderer)",
                executablePath: "\(chromeBundle)/Google Chrome Helper (Renderer)",
                bundleIdentifier: nil,
                memoryBytes: 300,
                memoryMetric: .physicalFootprint,
                physicalFootprintBytes: 300,
                residentBytes: 150
            ),
            ProcessInventoryEntry(
                pid: 200,
                parentPID: 1,
                name: "node",
                executablePath: "/opt/homebrew/bin/node",
                bundleIdentifier: nil,
                memoryBytes: 400,
                memoryMetric: .physicalFootprint,
                physicalFootprintBytes: 400,
                residentBytes: 400
            )
        ]

        let aggregation = ProcessMemoryAggregator.aggregate(
            inventory: inventory,
            applications: [chrome],
            limit: 8
        )

        guard let chromeSnapshot = aggregation.snapshots.first(where: { $0.name == "Google Chrome" }),
              let nodeSnapshot = aggregation.snapshots.first(where: { $0.name == "node" }) else {
            preconditionFailure("Expected grouped app and standalone process rows")
        }

        precondition(chromeSnapshot.memoryBytes == 600, "Chrome helpers must be grouped under the app")
        precondition(chromeSnapshot.processIDs == [100, 101, 102], "Chrome ownership must be deterministic")
        precondition(chromeSnapshot.groupKind == .application, "Chrome must be an application group")
        precondition(chromeSnapshot.residentBytes == 300, "Validation RSS must sum the same Chrome PIDs")
        precondition(chromeSnapshot.residentProcessCount == 3, "Validation RSS must be available for each Chrome PID")
        precondition(chromeSnapshot.physicalFootprintProcessCount == 3, "Chrome footprint PID count must be explicit")
        precondition(chromeSnapshot.residentFallbackProcessCount == 0, "Chrome should not use RSS fallback when footprint is available")
        precondition(nodeSnapshot.memoryBytes == 400, "Standalone node process must remain visible")
        precondition(nodeSnapshot.processIDs == [200], "Standalone process must own only itself")

        let ownedPIDs = aggregation.snapshots.flatMap(\.processIDs)
        precondition(Set(ownedPIDs).count == ownedPIDs.count, "A PID must not appear in two rows")
        precondition(aggregation.duplicateAssignedPIDCount == 0, "Diagnostic duplicate PID invariant must remain zero")
        precondition(Set(ownedPIDs) == Set(inventory.map(\.pid)), "Every inventory PID must be assigned once")
        precondition(aggregation.ownershipByPID.count == inventory.count, "Ownership must cover every PID")
    }
}
