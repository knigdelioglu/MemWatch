import AppKit
import Foundation

extension DisplayCoordinator {
    @discardableResult
    func setHiDPIEnabled(_ enabled: Bool) async -> Bool {
        guard displayOperationsAllowed else { return false }
        let powerGeneration = displayPowerGeneration
        do {
            let target = try HiDPITargetDisplayResolver.resolveSamsungS60UD()
            guard target.isOnline, target.isActive,
                  acceptsDisplayPowerGeneration(powerGeneration) else { return false }
            let _ = hiDPICoordinator.modeSwitcher.scanCGSModes(displayID: target.displayID)
            let status = hiDPICoordinator.modeSwitcher.refreshCGSModes(displayID: target.displayID)
            cgsManualModeSwitcherSummary = status
            cgsManualModeSwitcherStatusText = status.currentModeText

            guard status.isSamsungFingerprintMatched, !status.isBuiltin else {
                hiDPIStatusText = "Mevcut Mod: bilinmiyor"
                hiDPIActivationStatusText = "Samsung fingerprint doğrulanamadı."
                return false
            }

            let dynamicHiDPI = hiDPICoordinator.modeSwitcher.findBestHiDPIMode(
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 5120,
                targetPixelHeight: 2880,
                preferredRefreshRate: 100.0
            )
            let fallbackHiDPI = dynamicHiDPI == nil ? hiDPICoordinator.modeSwitcher.verifiedSamsungFallbackCandidate(
                modeID: 74,
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 5120,
                targetPixelHeight: 2880,
                preferredRefreshRate: 100.0,
                expectedHiDPI: true
            ) : nil

            let dynamicNormal = hiDPICoordinator.modeSwitcher.findBestNormalMode(
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                preferredRefreshRate: 100.0
            )
            let fallbackNormal = dynamicNormal == nil ? hiDPICoordinator.modeSwitcher.verifiedSamsungFallbackCandidate(
                modeID: 56,
                targetLogicalWidth: 2560,
                targetLogicalHeight: 1440,
                targetPixelWidth: 2560,
                targetPixelHeight: 1440,
                preferredRefreshRate: 100.0,
                expectedHiDPI: false
            ) : nil

            let selection = hiDPICoordinator.featureController.chooseActivationCandidate(
                enabled: enabled,
                dynamicHiDPI: dynamicHiDPI,
                fallbackHiDPI: fallbackHiDPI,
                dynamicNormal: dynamicNormal,
                fallbackNormal: fallbackNormal
            )

            guard let selectedCandidate = selection.selectedCandidate else {
                hiDPIActivationStatusText = selection.statusMessage
                updateStatus(selection.updateMessage)
                return false
            }

            let report = await hiDPICoordinator.modeSwitcher.applyCGSMode(modeID: Int(selectedCandidate.modeID))
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return false }
            if report.success {
                persistHiDPIState(enabled: enabled)
                hiDPIStatusText = "Mevcut Mod: \(selectedCandidate.logicalWidth)x\(selectedCandidate.logicalHeight) / \(selectedCandidate.pixelWidth)x\(selectedCandidate.pixelHeight) @\(Int(selectedCandidate.refreshRate.rounded()))Hz"
                isHiDPIActive = enabled
                updateStatus(selection.updateMessage)
                await reloadDisplayModes()
                return true
            }

            hiDPIActivationStatusText = report.failureReason ?? selection.statusMessage
            updateStatus(enabled ? "HiDPI açma başarısız" : "HiDPI kapatma başarısız")
            return false
        } catch {
            hiDPIStatusText = "Mevcut Mod: bilinmiyor"
            hiDPIActivationStatusText = "Samsung ekran bulunamadı."
            updateStatus("HiDPI işlemi başarısız")
            return false
        }
    }

    @objc func applyRetinaMode() {
        Task {
            await setHiDPIEnabled(true)
        }
    }

    @objc func disableRetinaModeAction() {
        disableRetinaMode()
    }

    func disableRetinaMode() {
        Task {
            await setHiDPIEnabled(false)
        }
    }

    @objc func emergencyResetRetinaModeAction() {
        emergencyResetRetinaMode()
    }

    func emergencyResetRetinaMode() {
        disableRetinaMode()
    }

    @objc func runHiDPIModePoolDiagnosticAction() {
        Task {
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            HiDPIDiagnostic.runModePoolDiagnostic()
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            updateStatus("HiDPI mode pool diagnostic completed")
        }
    }

    @objc func runExperimentalHiDPIActivationAction() {
        Task {
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            hiDPIActivationStatusText = "Private SLS transaction activation çalışıyor..."
            updateStatus("Private SLS transaction running")
            let result = PrivateHiDPIActivationEngine.shared.runSLSTransactionActivationExperiment()
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            hiDPIActivationStatusText = "\(result). Report: docs/generated/private_activation/sls_transaction_activation_experiment.md"
            await reloadDisplayModes()
        }
    }

    @objc func runCGSModeEnumerationAction() {
        Task {
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            do {
                let summary = try CGSModeEnumerationDiagnostic.runEnumeration()
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeEnumerationSummary = summary
                let reportPath = summary.reportURL.path
                let current = summary.currentModeID.map(String.init) ?? "unavailable"
                cgsModeEnumerationStatusText = "CGS current mode: \(current) | CGS count: \(summary.cgsModeCount) | public dup: \(summary.publicDuplicateModeCount) | Report: \(reportPath)"
                updateStatus("CGS mode enumeration completed")
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeEnumerationStatusText = "CGS mode enumeration failed: \(error.localizedDescription)"
                updateStatus("CGS mode enumeration failed")
            }
        }
    }

    @objc func runCGSMode74WithoutBetterDisplayCheckAction() {
        Task {
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            do {
                let summary = try CGSModeEnumerationDiagnostic.runWithoutBetterDisplayVerification()
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeEnumerationSummary = summary
                let reportPath = summary.reportURL.path
                let current = summary.currentModeID.map(String.init) ?? "unavailable"
                cgsModeEnumerationStatusText = "CGS current mode: \(current) | CGS count: \(summary.cgsModeCount) | public dup: \(summary.publicDuplicateModeCount) | mode74: \(summary.mode74 != nil ? "present" : "missing") | Report: \(reportPath)"
                updateStatus("CGS mode 74 check completed")
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeEnumerationStatusText = "CGS mode 74 check failed: \(error.localizedDescription)"
                updateStatus("CGS mode 74 check failed")
            }
        }
    }

    @objc func applyCGSMode56Action() {
        Task {
            guard displayOperationsAllowed else { return }
            guard let summary = cgsManualModeSwitcherSummary, summary.canApplyMode56 else {
                cgsManualModeSwitcherStatusText = "Current CGS Mode: unavailable"
                updateStatus("CGS mode 56 apply blocked")
                return
            }

            let powerGeneration = displayPowerGeneration
            let report = await hiDPICoordinator.modeSwitcher.applyCGSMode(modeID: 56)
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            refreshCGSModeSwitcherState()
            if report.success {
                updateStatus("CGS mode 56 applied")
            } else {
                updateStatus("CGS mode 56 apply failed")
            }
        }
    }

    @objc func applyCGSMode74Action() {
        Task {
            guard displayOperationsAllowed else { return }
            guard let summary = cgsManualModeSwitcherSummary, summary.canApplyMode74 else {
                cgsManualModeSwitcherStatusText = "Current CGS Mode: unavailable"
                updateStatus("CGS mode 74 apply blocked")
                return
            }

            let powerGeneration = displayPowerGeneration
            let report = await hiDPICoordinator.modeSwitcher.applyCGSMode(modeID: 74)
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            refreshCGSModeSwitcherState()
            if report.success {
                updateStatus("CGS mode 74 applied")
            } else {
                updateStatus("CGS mode 74 apply failed")
            }
        }
    }

    @objc func applyCGSMode56NormalQHDTransactionAction() {
        Task {
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            guard let summary = cgsModeEnumerationSummary else {
                cgsModeApplyExperimentStatusText = "CGS enumeration önce çalıştırılmalı."
                updateStatus("CGS mode 56 apply blocked")
                return
            }

            guard summary.mode56IsNormalQHD else {
                cgsModeApplyExperimentStatusText = "Mode 56 doğrulanmadı; apply pasif."
                updateStatus("CGS mode 56 apply blocked")
                return
            }

            do {
                let experiment = try CGSModeEnumerationDiagnostic.runMode56NormalQHDApplyExperiment(using: cgsModeApplyExperimentSummary)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeApplyExperimentSummary = experiment
                cgsModeEnumerationSummary = experiment.finalSummary
                let reportPath = experiment.reportURL.path
                cgsModeApplyExperimentStatusText = "Mode 56: \(experiment.mode56Outcome?.applyResultDescription ?? "not attempted") | Final: \(experiment.finalSummary.activeModeDescription) | Report: \(reportPath)"
                updateStatus("CGS mode 56 apply completed")
                await reloadDisplayModes()
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeApplyExperimentStatusText = "CGS mode 56 apply failed: \(error.localizedDescription)"
                updateStatus("CGS mode 56 apply failed")
            }
        }
    }

    @objc func applyCGSMode74TransactionAction() {
        Task {
            guard displayOperationsAllowed else { return }
            let powerGeneration = displayPowerGeneration
            guard let summary = cgsModeEnumerationSummary else {
                cgsModeApplyExperimentStatusText = "CGS enumeration önce çalıştırılmalı."
                updateStatus("CGS mode 74 apply blocked")
                return
            }

            guard summary.canApplyMode74Transaction else {
                cgsModeApplyExperimentStatusText = "Mode 74 doğrulanmadı; apply pasif."
                updateStatus("CGS mode 74 apply blocked")
                return
            }

            do {
                let experiment = try CGSModeEnumerationDiagnostic.runMode74ApplyExperiment(using: cgsModeApplyExperimentSummary)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeApplyExperimentSummary = experiment
                cgsModeEnumerationSummary = experiment.finalSummary
                let reportPath = experiment.reportURL.path
                cgsModeApplyExperimentStatusText = "Mode 74: \(experiment.mode74Outcome?.applyResultDescription ?? "not attempted") | Final: \(experiment.finalSummary.activeModeDescription) | Report: \(reportPath)"
                updateStatus("CGS mode 74 apply completed")
                await reloadDisplayModes()
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                cgsModeApplyExperimentStatusText = "CGS mode 74 apply failed: \(error.localizedDescription)"
                updateStatus("CGS mode 74 apply failed")
            }
        }
    }

    func startCalibration() {
        let key = activeDisplayKey
        let settings = store.ensureSettings(for: key)
        calibrationSession = CalibrationSession(
            displayKey: key,
            profileID: settings.selectedProfileID,
            step: .low,
            lowLux: nil,
            midLux: nil,
            highLux: nil
        )
        updateAutoBrightnessTitle()
        updateCalibrationStatus()
    }

    func captureCalibrationStep() {
        guard var session = calibrationSession, let lux = lastSmoothedLux else { return }
        switch session.step {
        case .low:
            session.lowLux = lux
            session.step = .mid
        case .mid:
            session.midLux = lux
            session.step = .high
        case .high:
            session.highLux = lux
            finalizeCalibration(session)
            return
        }
        calibrationSession = session
        updateCalibrationStatus()
    }

    func cancelCalibration() {
        guard calibrationSession != nil else { return }
        calibrationSession = nil
        updateAutoBrightnessTitle()
        updateStatus("Calibration cancelled")
    }

    func finalizeCalibration(_ session: CalibrationSession) {
        guard
            let lowLux = session.lowLux,
            let midLux = session.midLux,
            let highLux = session.highLux
        else {
            cancelCalibration()
            return
        }

        let calibration = DisplayCalibration(lowLux: lowLux, midLux: midLux, highLux: highLux)
        store.setCalibration(calibration, for: session.displayKey)
        calibrationSession = nil
        updateAutoBrightnessTitle()
        updateStatus("Calibration saved")
        Task {
            await tick()
        }
    }
}
