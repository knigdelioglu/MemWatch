import Foundation
import CoreGraphics

@MainActor
final class HiDPIRefreshService {
    struct Snapshot {
        let succeeded: Bool
        let availableModes: [PhysicalDisplayMode]
        let manualModeSwitcherSummary: CGSModeSwitcherStatus?
        let manualModeSwitcherStatusText: String
        let dynamicSelectionState: CGSDynamicModeSelectionState?
        let selectedHiDPICandidate: CGSDisplayModeCandidate?
        let selectedNormalCandidate: CGSDisplayModeCandidate?
        let samsungFallbackUsed: Bool
        let isHiDPIActive: Bool
        let hiDPIStatusText: String
        let hiDPIActivationStatusText: String
        let statusMessage: String?
    }

    private let modeSwitcher: CGSModeSwitcher
    private let featureController: HiDPIFeatureController

    init(
        modeSwitcher: CGSModeSwitcher,
        featureController: HiDPIFeatureController = HiDPIFeatureController()
    ) {
        self.modeSwitcher = modeSwitcher
        self.featureController = featureController
    }

    func reloadDisplayModes(currentActivationStatusText: String) async -> Snapshot {
        do {
            let target = try HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics()
            guard target.isOnline, target.isActive else {
                return unavailableSnapshot()
            }
            _ = modeSwitcher.scanCGSModes(displayID: target.displayID)

            return refreshState(
                displayID: target.displayID,
                currentActivationStatusText: currentActivationStatusText,
                statusMessage: nil
            )
        } catch {
            return Snapshot(
                succeeded: false,
                availableModes: [],
                manualModeSwitcherSummary: nil,
                manualModeSwitcherStatusText: "Current CGS Mode: unavailable",
                dynamicSelectionState: nil,
                selectedHiDPICandidate: nil,
                selectedNormalCandidate: nil,
                samsungFallbackUsed: false,
                isHiDPIActive: false,
                hiDPIStatusText: "Mevcut Mod: bilinmiyor",
                hiDPIActivationStatusText: "HiDPI modu sistem listesinde bulunamadı. Override/configuration kontrolü gerekiyor.",
                statusMessage: nil
            )
        }
    }

    func refreshCGSModeSwitcherState() -> CGSModeSwitcherStatus? {
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UD(),
              target.isOnline,
              target.isActive else {
            return nil
        }

        return modeSwitcher.refreshCGSModes(displayID: target.displayID)
    }

    private func refreshState(
        displayID: CGDirectDisplayID,
        currentActivationStatusText: String,
        statusMessage: String?
        ) -> Snapshot {
        _ = modeSwitcher.scanCGSModes(displayID: displayID)
        let availableModes = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        let summary = modeSwitcher.refreshCGSModes(displayID: displayID)
        let selection = featureController.buildDynamicSelection(
            using: modeSwitcher,
            selectionState: modeSwitcher.currentDynamicSelectionState(),
            activeFingerprint: summary.activeFingerprint
        )

        _ = modeSwitcher.writeDynamicModeSelectionReport(
            displayID: displayID,
            selectedHiDPI: selection.hiCandidate,
            selectedNormal: selection.normalCandidate,
            samsungFallbackUsed: selection.samsungFallbackUsed
        )

        return Snapshot(
            succeeded: true,
            availableModes: availableModes,
            manualModeSwitcherSummary: summary,
            manualModeSwitcherStatusText: summary.currentModeText,
            dynamicSelectionState: selection.selectionState,
            selectedHiDPICandidate: selection.hiCandidate,
            selectedNormalCandidate: selection.normalCandidate,
            samsungFallbackUsed: selection.samsungFallbackUsed,
            isHiDPIActive: HiDPIFeatureController.isHiDPIActive(activeFingerprint: summary.activeFingerprint),
            hiDPIStatusText: hiDPIStatusText(for: summary),
            hiDPIActivationStatusText: hiDPIActivationStatusText(
                currentText: currentActivationStatusText,
                summary: summary,
                selectedHiDPICandidate: selection.hiCandidate,
                overrideReason: nil
            ),
            statusMessage: statusMessage
        )
    }

    private func unavailableSnapshot() -> Snapshot {
        Snapshot(
            succeeded: false,
            availableModes: [],
            manualModeSwitcherSummary: nil,
            manualModeSwitcherStatusText: "Current CGS Mode: unavailable",
            dynamicSelectionState: nil,
            selectedHiDPICandidate: nil,
            selectedNormalCandidate: nil,
            samsungFallbackUsed: false,
            isHiDPIActive: false,
            hiDPIStatusText: "Mevcut Mod: bilinmiyor",
            hiDPIActivationStatusText: "HiDPI modu sistem listesinde bulunamadı. Override/configuration kontrolü gerekiyor.",
            statusMessage: nil
        )
    }

    private func hiDPIStatusText(for summary: CGSModeSwitcherStatus) -> String {
        guard summary.isSamsungFingerprintMatched, !summary.isBuiltin else {
            return "Mevcut Mod: bilinmiyor"
        }

        return summary.friendlyCurrentModeText
    }

    private func hiDPIActivationStatusText(
        currentText: String,
        summary: CGSModeSwitcherStatus,
        selectedHiDPICandidate: CGSDisplayModeCandidate?,
        overrideReason: String?
    ) -> String {
        guard summary.isSamsungFingerprintMatched, !summary.isBuiltin else {
            return currentText
        }

        if let overrideReason {
            return overrideReason
        }

        if HiDPIStateStore.isHiDPIEnabled() {
            return HiDPIStateStore.stateText() ?? "HiDPI enabled"
        }

        if selectedHiDPICandidate != nil {
            return "HiDPI disabled"
        }

        return "Uygun HiDPI modu CGS mode listesinde bulunamadı."
    }
}
