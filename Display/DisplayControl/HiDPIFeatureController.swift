import Foundation

struct HiDPIDynamicSelectionResult {
    let selectionState: CGSDynamicModeSelectionState
    let hiCandidate: CGSDisplayModeCandidate?
    let normalCandidate: CGSDisplayModeCandidate?
    let samsungFallbackUsed: Bool
}

struct HiDPIActivationCandidateSelection {
    let selectedCandidate: CGSDisplayModeCandidate?
    let statusMessage: String
    let updateMessage: String
}

struct HiDPIReapplyDecision {
    let shouldApply: Bool
    let reason: String
}

final class HiDPIFeatureController {
    let targetLogicalWidth: Int
    let targetLogicalHeight: Int
    let targetHiDPIWidth: Int
    let targetHiDPIHeight: Int
    let targetNormalWidth: Int
    let targetNormalHeight: Int
    let preferredRefreshRate: Double
    let hiDPIModeID: Int32
    let normalModeID: Int32

    init(
        targetLogicalWidth: Int = 2560,
        targetLogicalHeight: Int = 1440,
        targetHiDPIWidth: Int = 5120,
        targetHiDPIHeight: Int = 2880,
        targetNormalWidth: Int = 2560,
        targetNormalHeight: Int = 1440,
        preferredRefreshRate: Double = 100.0,
        hiDPIModeID: Int32 = 74,
        normalModeID: Int32 = 56
    ) {
        self.targetLogicalWidth = targetLogicalWidth
        self.targetLogicalHeight = targetLogicalHeight
        self.targetHiDPIWidth = targetHiDPIWidth
        self.targetHiDPIHeight = targetHiDPIHeight
        self.targetNormalWidth = targetNormalWidth
        self.targetNormalHeight = targetNormalHeight
        self.preferredRefreshRate = preferredRefreshRate
        self.hiDPIModeID = hiDPIModeID
        self.normalModeID = normalModeID
    }

    @MainActor
    func buildDynamicSelection(
        using modeSwitcher: CGSModeSwitcher,
        selectionState: CGSDynamicModeSelectionState?,
        activeFingerprint: CGSActiveModeFingerprint?
    ) -> HiDPIDynamicSelectionResult {
        let dynamicHiDPI = modeSwitcher.findBestHiDPIMode(
            targetLogicalWidth: targetLogicalWidth,
            targetLogicalHeight: targetLogicalHeight,
            targetPixelWidth: targetHiDPIWidth,
            targetPixelHeight: targetHiDPIHeight,
            preferredRefreshRate: preferredRefreshRate
        )
        let dynamicNormal = modeSwitcher.findBestNormalMode(
            targetLogicalWidth: targetLogicalWidth,
            targetLogicalHeight: targetLogicalHeight,
            preferredRefreshRate: preferredRefreshRate
        )

        let fallbackHi = dynamicHiDPI == nil ? modeSwitcher.verifiedSamsungFallbackCandidate(
            modeID: Int(hiDPIModeID),
            targetLogicalWidth: targetLogicalWidth,
            targetLogicalHeight: targetLogicalHeight,
            targetPixelWidth: targetHiDPIWidth,
            targetPixelHeight: targetHiDPIHeight,
            preferredRefreshRate: preferredRefreshRate,
            expectedHiDPI: true
        ) : nil

        let fallbackNormal = dynamicNormal == nil ? modeSwitcher.verifiedSamsungFallbackCandidate(
            modeID: Int(normalModeID),
            targetLogicalWidth: targetLogicalWidth,
            targetLogicalHeight: targetLogicalHeight,
            targetPixelWidth: targetNormalWidth,
            targetPixelHeight: targetNormalHeight,
            preferredRefreshRate: preferredRefreshRate,
            expectedHiDPI: false
        ) : nil

        let selectedHi = dynamicHiDPI ?? fallbackHi
        let selectedNormal = dynamicNormal ?? fallbackNormal

        let samsungFallbackUsed: Bool
        if let activeFingerprint {
            let hiMatches = matchesFingerprint(selectedHi, activeFingerprint: activeFingerprint)
            let normalMatches = matchesFingerprint(selectedNormal, activeFingerprint: activeFingerprint)

            samsungFallbackUsed =
                (hiMatches && dynamicHiDPI == nil && fallbackHi != nil) ||
                (normalMatches && dynamicNormal == nil && fallbackNormal != nil)
        } else {
            samsungFallbackUsed = false
        }

        return HiDPIDynamicSelectionResult(
            selectionState: selectionState ?? CGSDynamicModeSelectionState(
                currentModeID: nil,
                currentModeText: "Current CGS Mode: unavailable",
                modeCount: 0,
                publicDuplicateModeCount: 0,
                dynamicHiDPICandidate: nil,
                dynamicNormalCandidate: nil,
                samsungFallbackUsed: false,
                samsungFallbackCandidate: nil
            ),
            hiCandidate: selectedHi,
            normalCandidate: selectedNormal,
            samsungFallbackUsed: samsungFallbackUsed
        )
    }

    static func isHiDPIActive(activeFingerprint: CGSActiveModeFingerprint?) -> Bool {
        guard let activeFingerprint else { return false }
        return activeFingerprint.pixelWidth > activeFingerprint.logicalWidth ||
            activeFingerprint.pixelHeight > activeFingerprint.logicalHeight
    }

    func chooseActivationCandidate(
        enabled: Bool,
        dynamicHiDPI: CGSDisplayModeCandidate?,
        fallbackHiDPI: CGSDisplayModeCandidate?,
        dynamicNormal: CGSDisplayModeCandidate?,
        fallbackNormal: CGSDisplayModeCandidate?
    ) -> HiDPIActivationCandidateSelection {
        if enabled {
            let selected = dynamicHiDPI ?? fallbackHiDPI
            return HiDPIActivationCandidateSelection(
                selectedCandidate: selected,
                statusMessage: selected == nil ? "Uygun HiDPI modu CGS mode listesinde bulunamadı." : "",
                updateMessage: selected == nil ? "HiDPI modu sistem listesinde bulunamadı." : "HiDPI enabled"
            )
        }

        let selected = dynamicNormal ?? fallbackNormal
        return HiDPIActivationCandidateSelection(
            selectedCandidate: selected,
            statusMessage: selected == nil ? "Uygun normal mod CGS mode listesinde bulunamadı." : "",
            updateMessage: selected == nil ? "HiDPI kapatma başarısız" : "HiDPI disabled"
        )
    }

    func shouldReapplyHiDPI(
        activeFingerprint: CGSActiveModeFingerprint?,
        selectedCandidate: CGSDisplayModeCandidate?
    ) -> HiDPIReapplyDecision {
        guard let selectedCandidate else {
            return HiDPIReapplyDecision(
                shouldApply: false,
                reason: "HiDPI modu sistem listesinde bulunamadı."
            )
        }

        guard let activeFingerprint else {
            return HiDPIReapplyDecision(
                shouldApply: true,
                reason: "Active fingerprint unavailable."
            )
        }

        let matches = matchesFingerprint(selectedCandidate, activeFingerprint: activeFingerprint)
        return HiDPIReapplyDecision(
            shouldApply: !matches,
            reason: matches ? "Ekran zaten seçili HiDPI modunda." : "Reapply required."
        )
    }

    private func matchesFingerprint(_ candidate: CGSDisplayModeCandidate?, activeFingerprint: CGSActiveModeFingerprint) -> Bool {
        guard let candidate else { return false }
        return candidate.logicalWidth == activeFingerprint.logicalWidth &&
            candidate.logicalHeight == activeFingerprint.logicalHeight &&
            candidate.pixelWidth == activeFingerprint.pixelWidth &&
            candidate.pixelHeight == activeFingerprint.pixelHeight &&
            abs(candidate.refreshRate - activeFingerprint.refreshRateHz) < 0.1
    }
}
