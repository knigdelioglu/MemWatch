import Foundation

@MainActor
final class AppServices {
    let pollingScheduler: PollingScheduler
    let monitoring: MonitoringService
    let cleanup: CleanupCoordinator
    let capabilities: CapabilityRegistry
    let display: DisplayCoordinator

    init() {
        let scheduler = PollingScheduler()
        let capabilityRegistry = CapabilityRegistry()

        pollingScheduler = scheduler
        capabilities = capabilityRegistry
        monitoring = MonitoringService(scheduler: scheduler)
        cleanup = CleanupCoordinator()
        display = DisplayCoordinator(
            scheduler: scheduler,
            capabilityRegistry: capabilityRegistry
        )
    }

    func start() {
        monitoring.start()
        display.start()
    }

    func stop() {
        display.stop()
        monitoring.stop()
        pollingScheduler.stop()
    }
}
