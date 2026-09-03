import Foundation

extension DisplayCoordinator {
    var displayConnectionController: DisplayConnectionController {
        .shared
    }

    func refreshDisplayConnectionState() {
        guard displayOperationsAllowed else { return }
        let result = displayConnectionController.reconcileDesiredState()
        if result.phase == .softwareDisconnected {
            _ = applySoftwareDisconnectedDisplayStateIfNeeded()
        }
    }

    func toggleExternalDisplayConnection() {
        guard displayOperationsAllowed else { return }
        Task { @MainActor in
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            let result = await displayConnectionController.toggle()
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            statusText = result.message

            switch result.phase {
            case .connected:
                // Reuse the existing DDC/HiDPI rediscovery pipeline after reconnect.
                refreshDisplay()
                HiDPIReapplyService.shared.triggerReapplyDebounced()
            case .softwareDisconnected:
                // Do not run normal DDC discovery for an intentionally disabled display.
                _ = applySoftwareDisconnectedDisplayStateIfNeeded()
            default:
                break
            }
        }
    }
}
