import AppKit
import Foundation

extension DisplayCoordinator {
    func performMonitorVolumeKeyAction(_ action: MonitorVolumeKeyAction) -> Bool {
        Task {
            switch action {
            case .increase:
                await adjustMonitorVolume(by: 5)
            case .decrease:
                await adjustMonitorVolume(by: -5)
            case .mute:
                await toggleMuteForSettings()
            }
        }
        return true
    }

    func adjustMonitorVolumeForSettings(by delta: Int) {
        Task { await adjustMonitorVolume(by: delta) }
    }

    func toggleMuteForSettingsSync() {
        Task { await toggleMuteForSettings() }
    }

    @discardableResult
    func adjustMonitorVolume(by delta: Int) async -> Bool {
        let (success, _) = await brightnessCoordinator.writer.changeVolume(delta, preferredKey: activeDisplayKey)
        if success {
            let fallbackBase = monitorVolumeControlValue
            currentVolume = min(100, max(0, fallbackBase + delta))
            if let currentVolume {
                volumeCoordinator.record(currentVolume)
            }
            if let currentVolume {
                updateStatus("Volume \(currentVolume)%")
            } else {
                updateStatus("Volume changed")
            }
        } else {
            updateStatus("Volume change failed")
        }
        return success
    }

    @discardableResult
    func setMonitorVolume(_ percent: Int) async -> Bool {
        let clamped = min(100, max(0, percent))
        let (success, _) = await brightnessCoordinator.writer.setVolume(clamped, preferredKey: activeDisplayKey)
        if success {
            currentVolume = clamped
            volumeCoordinator.record(clamped)
            updateStatus("Volume \(clamped)%")
        } else {
            updateStatus("Volume set failed")
        }
        return success
    }

    @discardableResult
    func toggleMuteForSettings() async -> Bool {
        let volume = monitorVolumeControlValue
        let isMuted = volume == 0
        let targetVolume = isMuted ? max(1, volumeCoordinator.lastNonZeroVolume) : 0
        let (success, _) = await brightnessCoordinator.writer.setMute(!isMuted, preferredKey: activeDisplayKey)
        if success {
            currentVolume = targetVolume
            volumeCoordinator.record(targetVolume)
            updateStatus(!isMuted ? "Muted" : "Unmuted")
        } else {
            updateStatus("Mute failed")
        }
        return success
    }

    func setMonitorVolumeForSettings(_ percent: Int) {
        Task { await setMonitorVolume(percent) }
    }

    func setMonitorBrightness(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        pauseAutoBrightnessTemporarily()
        Task {
            let result = await brightnessCoordinator.writer.setBrightness(clamped, preferredKey: activeDisplayKey)
            let actualAfter = result.actualUIPercentAfter ?? result.readbackBrightnessPercent ?? clamped
            let matchedTarget = result.matchedTarget == true
            print(
                """
                requestedUIPercent=\(clamped)
                rawMax=\(result.rawMax.map(String.init) ?? "unavailable")
                computedRawTarget=\(result.computedRawTarget.map(String.init) ?? "unavailable")
                rawBefore=\(result.rawBefore.map(String.init) ?? "unavailable")
                writeResult=\(result.status.rawValue)
                rawAfter=\(result.rawAfter.map(String.init) ?? "unavailable")
                actualUIPercentAfter=\(actualAfter)
                matchedTarget=\(matchedTarget ? "YES" : "NO")
                """
            )
            if result.status == .success || result.status == .writeAcceptedButReadbackLimited {
                lastSentBrightness = clamped
                lastWriteDate = Date()
                beginManualBrightnessOverride()
                if let readback = result.actualUIPercentAfter ?? result.readbackBrightnessPercent {
                    lastBrightnessReadDate = lastWriteDate
                    store.setLastBrightness(readback, for: activeDisplayKey)
                } else {
                    store.setLastBrightness(clamped, for: activeDisplayKey)
                }
                applyBrightnessWriteResult(requested: clamped, source: .quickPanelSlider, result: result)
                if result.status == .writeAcceptedButReadbackLimited {
                    updateStatus(result.message)
                } else {
                    updateStatus(result.actualUIPercentAfter.map { "Brightness \($0)%" } ?? "Brightness \(clamped)%")
                }
            } else {
                applyBrightnessWriteResult(requested: clamped, source: .quickPanelSlider, result: result)
                updateStatus(result.message.isEmpty ? "Parlaklık yazılamadı" : "Parlaklık yazılamadı: \(result.message)")
            }
        }
    }

    @discardableResult
    func setInternalBrightness(_ percent: Int) -> Bool {
        guard let controller = brightnessCoordinator.internalDisplayController else {
            updateStatus("Dahili parlaklık kontrolü kullanılamıyor")
            return false
        }

        let (success, message) = controller.setBrightness(percent)
        if success {
            currentInternalBrightness = controller.currentBrightness() ?? min(100, max(0, percent))
            updateStatus("Dahili parlaklık %\(currentInternalBrightness ?? percent)")
        } else {
            currentInternalBrightness = controller.currentBrightness()
            updateStatus("Dahili parlaklık ayarlanamadı: \(message)")
        }
        return success
    }

    func pauseAutoBrightnessTemporarily(for duration: TimeInterval = 20) {
        beginManualBrightnessOverride(fallbackDuration: duration)
    }

    func setAutoBrightnessEnabled(_ enabled: Bool) {
        guard autoBrightnessEnabled != enabled else { return }
        autoBrightnessEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "AmbientSync.AutoBrightnessEnabled")

        if enabled {
            clearManualBrightnessOverride()
            updateStatus("Otomatik parlaklık açıldı")
        } else {
            pendingTargetCandidate = nil
            updateBrightnessState { state in
                state.isAutoBrightnessEnabled = false
                state.isManualOverrideActive = false
                state.isBrightnessWriteSuppressed = true
                state.suppressionReason = "Automatic brightness is disabled"
            }
            updateStatus("Otomatik parlaklık kapalı")
        }
    }

    func beginManualBrightnessOverride(fallbackDuration: TimeInterval = 20) {
        if manualBrightnessOverrideStartLux == nil {
            manualBrightnessOverrideStartLux = lastSmoothedLux ?? currentLux
        }
        if manualBrightnessOverrideStartLux == nil {
            manualBrightnessOverrideUntil = max(manualBrightnessOverrideUntil, Date().addingTimeInterval(fallbackDuration))
        } else {
            manualBrightnessOverrideUntil = .distantPast
        }
        pendingTargetCandidate = nil
        updateBrightnessState { state in
            state.isManualOverrideActive = true
            state.isAutoBrightnessEnabled = false
        }
    }

    func clearManualBrightnessOverride() {
        manualBrightnessOverrideStartLux = nil
        manualBrightnessOverrideUntil = .distantPast
        pendingTargetCandidate = nil
        updateBrightnessState { state in
            state.isManualOverrideActive = false
            state.isAutoBrightnessEnabled = autoBrightnessEnabled && calibrationSession == nil
        }
    }

    func shouldHoldManualBrightnessOverride(currentLux: Double, now: Date) -> Bool {
        let shouldContinue = brightnessAutoController.shouldContinueManualOverride(
            currentLux: currentLux,
            startLux: manualBrightnessOverrideStartLux,
            overrideUntil: manualBrightnessOverrideUntil,
            now: now
        )

        guard shouldContinue else {
            clearManualBrightnessOverride()
            return false
        }

        if manualBrightnessOverrideStartLux == nil && now < manualBrightnessOverrideUntil {
            manualBrightnessOverrideStartLux = currentLux
            manualBrightnessOverrideUntil = .distantPast
        }

        return true
    }

}
