import Foundation

extension DisplayCoordinator {
    var displayConnectionController: DisplayConnectionController {
        .shared
    }

    func refreshDisplayConnectionState() {
        guard displayReadOperationsAllowed else { return }
        let result = displayConnectionController.reconcileDesiredState()
        if result.phase == .softwareDisconnected {
            _ = applySoftwareDisconnectedDisplayStateIfNeeded()
        }
    }

    func toggleExternalDisplayConnection() {
        // Connection recovery is the transition that can make the target
        // ready again, so it cannot require the already-ready target gate.
        // It is still blocked across sleep/wake and controlled post-wake work.
        guard displayInteractiveOperationsAllowed else { return }
        Task { @MainActor in
            guard displayInteractiveOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            let result = await displayConnectionController.toggle()
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            statusText = result.message

            switch result.phase {
            case .connected:
                // Reuse the existing DDC/HiDPI rediscovery pipeline after reconnect.
                refreshDisplay()
                beginTargetDisplayReadinessRecoveryIfNeeded(for: powerGeneration)
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
