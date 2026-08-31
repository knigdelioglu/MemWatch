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

    func reloadDisplayModes(currentActivationStatusText: String) -> Snapshot {
        do {
            let target = try HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics()
            _ = modeSwitcher.scanCGSModes(displayID: target.displayID)

            let initialState = refreshState(
                displayID: target.displayID,
                currentActivationStatusText: currentActivationStatusText,
                statusMessage: nil
            )

            if HiDPIStateStore.isHiDPIEnabled() {
                return autoReapplyIfNeeded(
                    targetDisplayID: target.displayID,
                    currentActivationStatusText: currentActivationStatusText,
                    initialState: initialState
                )
            }

            return initialState
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
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UD() else {
            return nil
        }

        return modeSwitcher.refreshCGSModes(displayID: target.displayID)
    }

    private func autoReapplyIfNeeded(
        targetDisplayID: CGDirectDisplayID,
        currentActivationStatusText: String,
        initialState: Snapshot
    ) -> Snapshot {
        guard let summary = initialState.manualModeSwitcherSummary,
              summary.isSamsungFingerprintMatched,
              !summary.isBuiltin else {
            return initialState
        }

        guard let hiCandidate = modeSwitcher.findBestHiDPIMode(
            targetLogicalWidth: 2560,
            targetLogicalHeight: 1440,
            targetPixelWidth: 5120,
            targetPixelHeight: 2880,
            preferredRefreshRate: 100.0
        ) ?? modeSwitcher.verifiedSamsungFallbackCandidate(
            modeID: 74,
            targetLogicalWidth: 2560,
            targetLogicalHeight: 1440,
            targetPixelWidth: 5120,
            targetPixelHeight: 2880,
            preferredRefreshRate: 100.0,
            expectedHiDPI: true
        ) else {
            return Snapshot(
                succeeded: true,
                availableModes: initialState.availableModes,
                manualModeSwitcherSummary: initialState.manualModeSwitcherSummary,
                manualModeSwitcherStatusText: initialState.manualModeSwitcherStatusText,
                dynamicSelectionState: initialState.dynamicSelectionState,
                selectedHiDPICandidate: initialState.selectedHiDPICandidate,
                selectedNormalCandidate: initialState.selectedNormalCandidate,
                samsungFallbackUsed: initialState.samsungFallbackUsed,
                isHiDPIActive: initialState.isHiDPIActive,
                hiDPIStatusText: initialState.hiDPIStatusText,
                hiDPIActivationStatusText: "Uygun HiDPI modu CGS mode listesinde bulunamadı.",
                statusMessage: nil
            )
        }

        if summary.activeFingerprint?.modeID == hiCandidate.modeID {
            HiDPIStateStore.setHiDPIEnabled(true)
            HiDPIStateStore.setStateText("HiDPI enabled")

            return Snapshot(
                succeeded: true,
                availableModes: initialState.availableModes,
                manualModeSwitcherSummary: initialState.manualModeSwitcherSummary,
                manualModeSwitcherStatusText: initialState.manualModeSwitcherStatusText,
                dynamicSelectionState: initialState.dynamicSelectionState,
                selectedHiDPICandidate: initialState.selectedHiDPICandidate,
                selectedNormalCandidate: initialState.selectedNormalCandidate,
                samsungFallbackUsed: initialState.samsungFallbackUsed,
                isHiDPIActive: initialState.isHiDPIActive,
                hiDPIStatusText: initialState.hiDPIStatusText,
                hiDPIActivationStatusText: HiDPIStateStore.stateText() ?? "HiDPI enabled",
                statusMessage: nil
            )
        }

        let report = modeSwitcher.applyCGSMode(modeID: Int(hiCandidate.modeID))
        let statusMessage = report.success ? "HiDPI enabled" : nil
        let activationStatusText = report.success
            ? (HiDPIStateStore.stateText() ?? "HiDPI enabled")
            : (report.failureReason ?? "Uygun HiDPI modu CGS mode listesinde bulunamadı.")

        let refreshed = refreshState(
            displayID: targetDisplayID,
            currentActivationStatusText: activationStatusText,
            statusMessage: statusMessage
        )

        if report.success {
            HiDPIStateStore.setHiDPIEnabled(true)
            HiDPIStateStore.setStateText("HiDPI enabled")
        }

        return Snapshot(
            succeeded: true,
            availableModes: refreshed.availableModes,
            manualModeSwitcherSummary: refreshed.manualModeSwitcherSummary,
            manualModeSwitcherStatusText: refreshed.manualModeSwitcherStatusText,
            dynamicSelectionState: refreshed.dynamicSelectionState,
            selectedHiDPICandidate: refreshed.selectedHiDPICandidate,
            selectedNormalCandidate: refreshed.selectedNormalCandidate,
            samsungFallbackUsed: refreshed.samsungFallbackUsed,
            isHiDPIActive: refreshed.isHiDPIActive,
            hiDPIStatusText: refreshed.hiDPIStatusText,
            hiDPIActivationStatusText: report.success
                ? (HiDPIStateStore.stateText() ?? "HiDPI enabled")
                : (report.failureReason ?? refreshed.hiDPIActivationStatusText),
            statusMessage: statusMessage
        )
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
