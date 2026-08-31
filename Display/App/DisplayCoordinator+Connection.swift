import Foundation

extension DisplayCoordinator {
    var displayConnectionController: DisplayConnectionController {
        .shared
    }

    func refreshDisplayConnectionState() {
        let result = displayConnectionController.reconcileDesiredState()
        if result.phase == .softwareDisconnected {
            _ = applySoftwareDisconnectedDisplayStateIfNeeded()
        }
    }

    func toggleExternalDisplayConnection() {
        Task { @MainActor in
            let result = await displayConnectionController.toggle()
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
