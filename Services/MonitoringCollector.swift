import Foundation

/// The immutable work request sent to the serialized monitoring worker.
struct MonitoringCollectionRequest: Sendable {
    let includeProcesses: Bool
    let includeStorage: Bool
}

/// A complete, immutable collection result. Optional storage means the worker
/// can keep the existing 30-second storage cadence without making every
/// lightweight monitoring tick enumerate mounted volumes.
struct MonitoringCollectionSnapshot: Sendable {
    let memory: MemorySnapshot
    let power: PowerSnapshot
    let diagnostics: SystemDiagnosticsSnapshot
    let storageVolumes: [StorageVolumeSnapshot]?
    let thermal: ThermalSnapshot
}

/// Actor boundary used by MonitoringService. Keeping the protocol actor-bound
/// makes test fakes obey the same isolation rules as the production worker.
protocol MonitoringCollecting: Actor {
    func collect(_ request: MonitoringCollectionRequest) async -> MonitoringCollectionSnapshot
}

/// Owns every stateful collector for the lifetime of one monitoring service.
/// In particular, SystemDiagnosticsCollector's CPU counters never move
/// between threads or collector instances.
actor MonitoringCollector: MonitoringCollecting {
    private let memoryCollector = MemoryCollector()
    private let powerCollector = PowerCollector()
    private let diagnosticsCollector = SystemDiagnosticsCollector()
    private let storageCollector = StorageCollector()
    private let thermalCollector: ThermalCollector

    init(thermalCollector: ThermalCollector? = nil) {
        self.thermalCollector = thermalCollector ?? ThermalCollector()
    }

    func collect(_ request: MonitoringCollectionRequest) async -> MonitoringCollectionSnapshot {
        MonitoringCollectionSnapshot(
            memory: memoryCollector.collect(),
            power: powerCollector.collect(),
            diagnostics: diagnosticsCollector.collect(includeProcesses: request.includeProcesses),
            storageVolumes: request.includeStorage ? storageCollector.collect() : nil,
            thermal: thermalCollector.collect()
        )
    }
}
