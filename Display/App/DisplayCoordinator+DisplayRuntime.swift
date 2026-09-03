import AppKit
import Foundation

extension DisplayCoordinator {
    func applySoftwareDisconnectedDisplayStateIfNeeded() -> Bool {
        guard displayOperationsAllowed else { return false }
        invalidateManualBrightnessWrites()
        invalidateManualVolumeWrites()
        cancelPendingManualBrightnessWrite()
        cancelPendingManualVolumeWrite()
        let connection = displayConnectionController.reconcileDesiredState()
        traceRuntime(
            "applySoftwareDisconnected result phase=\(connection.phase.rawValue) displayID=\(connection.displayID.map(String.init) ?? "nil") " +
                "online=\(connection.isOnline) active=\(connection.isActive)"
        )
        guard connection.phase == .softwareDisconnected else { return false }

        publishCurrentDisplayInfo(nil, reason: "software disconnect state applied")
        currentBrightness = nil
        currentVolume = nil
        pendingVolumeIntent = nil
        volumeKeyRouter?.setEnabled(false)
        availableModes = []
        isHiDPIActive = false
        hiDPIStatusText = "Samsung S60UD yazılımsal olarak ayrıldı"
        currentEDIDSummary = nil
        hdrBrightnessDiagnosticSummary = nil
        ddcBrightnessMaxDiagnosticSummary = nil
        ddcRawBrightnessProbeSummary = nil
        brightnessMappingDiagnosticSummary = nil
        clearManualBrightnessOverride()
        updateBrightnessState { state in
            state.isAutoBrightnessEnabled = false
            state.isBrightnessWriteSuppressed = true
            state.suppressionReason = "Harici ekran yazılımsal olarak ayrıldı"
        }
        updateStatus(connection.message)
        return true
    }

    func reloadDisplayInfo(reloadModes: Bool = true) async {
        guard displayOperationsAllowed else { return }
        let powerGeneration = displayPowerGeneration
        traceRuntime(
            "reloadDisplayInfo begin reloadModes=\(reloadModes) preferredKey=\(store.preferences.selectedDisplayKey ?? "nil") " +
                "currentDisplay=\(currentDisplayInfo?.displayKey ?? "nil")"
        )
        if applySoftwareDisconnectedDisplayStateIfNeeded() {
            traceRuntime("reloadDisplayInfo suppressed by software disconnect state")
            return
        }
        let previousDisplayKey = currentDisplayInfo?.displayKey
        let discoveredDisplay = await brightnessCoordinator.writer.refreshDisplay(preferredKey: store.preferences.selectedDisplayKey)
        guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
        traceRuntime(
            "writer.refreshDisplay result=\(discoveredDisplay?.displayKey ?? "nil") " +
                "previousDisplay=\(previousDisplayKey ?? "nil")"
        )
        if let display = discoveredDisplay {
            publishCurrentDisplayInfo(display, reason: "writer.refreshDisplay non-nil")
            store.setSelectedDisplayKey(display.displayKey)
            if display.displayKey != previousDisplayKey {
                invalidateManualBrightnessWrites()
                invalidateManualVolumeWrites()
                cancelPendingManualBrightnessWrite()
                cancelPendingManualVolumeWrite()
                luxFilter.reset()
                lastSentBrightness = store.lastBrightness(for: display.displayKey)
                lastWriteDate = .distantPast
                lastBrightnessReadDate = .distantPast
                lastDisplaySearchDate = Date()
                clearManualBrightnessOverride()
                brightnessLimiterCooldownDisplayKey = nil
                brightnessLimiterCooldownUntil = .distantPast
                currentVolume = nil
                pendingVolumeIntent = nil
                lastVolumeReadDate = .distantPast
                hdrBrightnessDiagnosticSummary = nil
                ddcBrightnessMaxDiagnosticSummary = nil
                ddcRawBrightnessProbeSummary = nil
                brightnessMappingDiagnosticSummary = nil
                brightnessState = BrightnessState()
                currentBrightness = nil
            }
            if currentBrightness == nil || display.displayKey != previousDisplayKey {
                let readback = await brightnessCoordinator.writer.readBrightness(preferredKey: display.displayKey)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                let fallback = readback ?? store.lastBrightness(for: display.displayKey)
                applyBrightnessReadback(readback, requestedFallback: fallback)
                lastBrightnessReadDate = Date()
            }
            updateAutoBrightnessTitle()
            await refreshCurrentVolume(force: true)
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            volumeKeyRouter?.setEnabled(true)
            // Publish display capabilities before the optional synchronous
            // HiDPI/CGS scan so discovery is visible even when that scan is
            // slow or unavailable.
            updateCapabilities()
            if reloadModes {
                await reloadDisplayModes()
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            }
        } else {
            invalidateManualBrightnessWrites()
            invalidateManualVolumeWrites()
            cancelPendingManualBrightnessWrite()
            cancelPendingManualVolumeWrite()
            publishCurrentDisplayInfo(nil, reason: "writer.refreshDisplay returned nil")
            currentBrightness = nil
            clearManualBrightnessOverride()
            currentVolume = nil
            pendingVolumeIntent = nil
            volumeKeyRouter?.setEnabled(false)
            self.availableModes = []
            self.isHiDPIActive = false
            hiDPIStatusText = "Samsung S60UD ekranı bulunamadı"
            hdrBrightnessDiagnosticSummary = nil
            ddcBrightnessMaxDiagnosticSummary = nil
            ddcRawBrightnessProbeSummary = nil
            brightnessMappingDiagnosticSummary = nil
            brightnessState = BrightnessState()
            updateCapabilities()
        }
    }

    func refreshInternalBrightness() {
        guard displayOperationsAllowed else { return }
        currentInternalBrightness = brightnessCoordinator.internalDisplayController?.currentBrightness()
    }

    func refreshDisplay() {
        refresh()
    }

    func refreshRuntimeState() {
        guard displayOperationsAllowed else { return }
        updateAutoBrightnessTitle()
        refreshInternalBrightness()
        Task {
            await tick()
        }
    }

    func updateCalibrationStatus() {
        guard let session = calibrationSession, let lux = lastSmoothedLux else { return }
        updateStatus("\(session.step.rawValue.capitalized) step: \(String(format: "%.0f", lux)) lux")
    }

    func refreshEDIDDiagnosticSummary() {
        guard displayOperationsAllowed else { return }
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            currentEDIDSummary = nil
            return
        }
        currentEDIDSummary = DisplayEDIDReader.shared.readEDID(for: target.displayID)
    }

    func readEDIDDiagnostic() {
        guard displayOperationsAllowed else { return }
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            currentEDIDSummary = nil
            updateStatus("EDID diagnostic: target display unavailable")
            return
        }

        let summary = DisplayEDIDReader.shared.readEDID(for: target.displayID)
        currentEDIDSummary = summary
        if let url = DisplayEDIDReader.shared.writeDiagnosticReport(summary: summary) {
            print("EDID diagnostic report written: \(url.path)")
            updateStatus("EDID diagnostic written")
        } else {
            print("EDID diagnostic report write failed")
            updateStatus("EDID diagnostic write failed")
        }
    }

    func readHDRBrightnessDiagnostic() {
        guard displayOperationsAllowed else { return }
        let powerGeneration = displayPowerGeneration
        Task { @MainActor in
            guard displayOperationsAllowed,
                  displayPowerGeneration == powerGeneration else { return }
            let summary = await hdrBrightnessDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            hdrBrightnessDiagnosticSummary = summary
            do {
                let url = try await hdrBrightnessDiagnostic.writeDiagnosticReport(summary: summary)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                print("HDR brightness diagnostic report written: \(url.path)")
                updateStatus("HDR brightness diagnostic written")
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                print("HDR brightness diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("HDR brightness diagnostic write failed")
            }
        }
    }

    func readDDCBrightnessMaxDiagnostic() {
        guard displayOperationsAllowed else { return }
        let powerGeneration = displayPowerGeneration
        Task { @MainActor in
            guard displayOperationsAllowed,
                  displayPowerGeneration == powerGeneration else { return }
            let summary = await ddcBrightnessMaxDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            ddcBrightnessMaxDiagnosticSummary = summary
            do {
                let url = try await ddcBrightnessMaxDiagnostic.writeDiagnosticReport(summary: summary)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                print("DDC brightness max diagnostic report written: \(url.path)")
                updateStatus("DDC brightness max diagnostic written")
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                print("DDC brightness max diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("DDC brightness max diagnostic write failed")
            }
        }
    }

    func readDDCRawBrightnessProbeDiagnostic() {
        guard displayOperationsAllowed else { return }
        let powerGeneration = displayPowerGeneration
        Task { @MainActor in
            guard displayOperationsAllowed,
                  displayPowerGeneration == powerGeneration else { return }
            let summary = await ddcRawBrightnessProbeDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            ddcRawBrightnessProbeSummary = summary
            do {
                let url = try await ddcRawBrightnessProbeDiagnostic.writeDiagnosticReport(summary: summary)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                print("DDC raw brightness probe report written: \(url.path)")
                updateStatus("DDC raw brightness probe written")
            } catch {
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                print("DDC raw brightness probe report write failed: \(error.localizedDescription)")
                updateStatus("DDC raw brightness probe write failed")
            }
        }
    }

    func readBrightnessMappingDiagnostic() {
        guard displayOperationsAllowed else { return }
        let powerGeneration = displayPowerGeneration
        Task { @MainActor in
            guard displayOperationsAllowed,
                  displayPowerGeneration == powerGeneration else { return }
            if let display = currentDisplayInfo {
                let readback = await brightnessCoordinator.writer.readBrightness(preferredKey: display.displayKey)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                let rawSample = await brightnessCoordinator.writer.readBrightnessRaw(preferredKey: display.displayKey)
                guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
                if let rawSample {
                    updateBrightnessState { state in
                        state.lastDDCRawCurrentBefore = rawSample.rawCurrent
                        state.lastDDCRawMax = rawSample.rawMax
                        state.lastDDCRawAfter = rawSample.rawCurrent
                        if let rawCurrent = rawSample.rawCurrent, let rawMax = rawSample.rawMax {
                            state.lastDDCActualPercentAfter = DDCBrightnessScale.uiPercent(fromRawCurrent: rawCurrent, rawMax: rawMax)
                        }
                    }
                }
                applyBrightnessReadback(readback, requestedFallback: store.lastBrightness(for: display.displayKey))
            }

            guard acceptsDisplayPowerGeneration(powerGeneration) else { return }
            let summary = brightnessMappingDiagnosticSummarySnapshot()
            brightnessMappingDiagnosticSummary = summary
            do {
                let url = try BrightnessMappingDiagnosticReporter.writeMarkdownReport(summary: summary)
                print("Brightness mapping diagnostic report written: \(url.path)")
                updateStatus("Brightness mapping diagnostic written")
            } catch {
                print("Brightness mapping diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("Brightness mapping diagnostic write failed")
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleKeepAwakeAction() {
        toggleKeepAwake()
    }

    @objc private func refreshDisplayAction() {
        refreshDisplay()
    }

    @objc private func readEDIDDiagnosticAction() {
        readEDIDDiagnostic()
    }

    @objc private func readHDRBrightnessDiagnosticAction() {
        readHDRBrightnessDiagnostic()
    }

    @objc private func readDDCBrightnessMaxDiagnosticAction() {
        readDDCBrightnessMaxDiagnostic()
    }

    @objc private func readDDCRawBrightnessProbeDiagnosticAction() {
        readDDCRawBrightnessProbeDiagnostic()
    }

    @objc private func decreaseVolumeAction() {
        adjustMonitorVolumeForSettings(by: -5)
    }

    @objc private func increaseVolumeAction() {
        adjustMonitorVolumeForSettings(by: 5)
    }

    @objc private func setVolumeFiftyAction() {
        setMonitorVolumeForSettings(50)
    }

    @objc private func toggleMuteAction() {
        toggleMuteForSettingsSync()
    }
}
