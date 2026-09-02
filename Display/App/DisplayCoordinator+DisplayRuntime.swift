import AppKit
import Foundation

extension DisplayCoordinator {
    func applySoftwareDisconnectedDisplayStateIfNeeded() -> Bool {
        let connection = displayConnectionController.reconcileDesiredState()
        guard connection.phase == .softwareDisconnected else { return false }

        currentDisplayInfo = nil
        currentBrightness = nil
        currentVolume = nil
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
        if applySoftwareDisconnectedDisplayStateIfNeeded() {
            return
        }
        let previousDisplayKey = currentDisplayInfo?.displayKey
        if let display = await brightnessCoordinator.writer.refreshDisplay(preferredKey: store.preferences.selectedDisplayKey) {
            currentDisplayInfo = display
            store.setSelectedDisplayKey(display.displayKey)
            if display.displayKey != previousDisplayKey {
                luxFilter.reset()
                lastSentBrightness = store.lastBrightness(for: display.displayKey)
                lastWriteDate = .distantPast
                lastBrightnessReadDate = .distantPast
                lastDisplaySearchDate = Date()
                clearManualBrightnessOverride()
                brightnessLimiterCooldownDisplayKey = nil
                brightnessLimiterCooldownUntil = .distantPast
                currentVolume = nil
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
                let fallback = readback ?? store.lastBrightness(for: display.displayKey)
                applyBrightnessReadback(readback, requestedFallback: fallback)
                lastBrightnessReadDate = Date()
            }
            updateAutoBrightnessTitle()
            await refreshCurrentVolume(force: true)
            volumeKeyRouter?.setEnabled(true)
            // Publish display capabilities before the optional synchronous
            // HiDPI/CGS scan so discovery is visible even when that scan is
            // slow or unavailable.
            updateCapabilities()
            if reloadModes {
                await reloadDisplayModes()
            }
        } else {
            currentDisplayInfo = nil
            currentBrightness = nil
            clearManualBrightnessOverride()
            currentVolume = nil
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
        currentInternalBrightness = brightnessCoordinator.internalDisplayController?.currentBrightness()
    }

    func refreshDisplay() {
        Task {
            await reloadDisplayInfo()
            refreshInternalBrightness()
            refreshEDIDDiagnosticSummary()
            await tick()
        }
    }

    func refreshRuntimeState() {
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
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            currentEDIDSummary = nil
            return
        }
        currentEDIDSummary = DisplayEDIDReader.shared.readEDID(for: target.displayID)
    }

    func readEDIDDiagnostic() {
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
        Task { @MainActor in
            let summary = await hdrBrightnessDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            hdrBrightnessDiagnosticSummary = summary
            do {
                let url = try await hdrBrightnessDiagnostic.writeDiagnosticReport(summary: summary)
                print("HDR brightness diagnostic report written: \(url.path)")
                updateStatus("HDR brightness diagnostic written")
            } catch {
                print("HDR brightness diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("HDR brightness diagnostic write failed")
            }
        }
    }

    func readDDCBrightnessMaxDiagnostic() {
        Task { @MainActor in
            let summary = await ddcBrightnessMaxDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            ddcBrightnessMaxDiagnosticSummary = summary
            do {
                let url = try await ddcBrightnessMaxDiagnostic.writeDiagnosticReport(summary: summary)
                print("DDC brightness max diagnostic report written: \(url.path)")
                updateStatus("DDC brightness max diagnostic written")
            } catch {
                print("DDC brightness max diagnostic report write failed: \(error.localizedDescription)")
                updateStatus("DDC brightness max diagnostic write failed")
            }
        }
    }

    func readDDCRawBrightnessProbeDiagnostic() {
        Task { @MainActor in
            let summary = await ddcRawBrightnessProbeDiagnostic.run(preferredDisplayKey: currentDisplayInfo?.displayKey)
            ddcRawBrightnessProbeSummary = summary
            do {
                let url = try await ddcRawBrightnessProbeDiagnostic.writeDiagnosticReport(summary: summary)
                print("DDC raw brightness probe report written: \(url.path)")
                updateStatus("DDC raw brightness probe written")
            } catch {
                print("DDC raw brightness probe report write failed: \(error.localizedDescription)")
                updateStatus("DDC raw brightness probe write failed")
            }
        }
    }

    func readBrightnessMappingDiagnostic() {
        Task { @MainActor in
            if let display = currentDisplayInfo {
                let readback = await brightnessCoordinator.writer.readBrightness(preferredKey: display.displayKey)
                let rawSample = await brightnessCoordinator.writer.readBrightnessRaw(preferredKey: display.displayKey)
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
        Task { await adjustMonitorVolume(by: -5) }
    }

    @objc private func increaseVolumeAction() {
        Task { await adjustMonitorVolume(by: 5) }
    }

    @objc private func setVolumeFiftyAction() {
        Task { await setMonitorVolume(50) }
    }

    @objc private func toggleMuteAction() {
        Task { await toggleMuteForSettings() }
    }
}
