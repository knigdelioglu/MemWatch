import AppKit
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeCoordinator {
    unowned let app: DisplayCoordinator
    private let featureController: KeepAwakeFeatureController
    private let keepAwakeController: KeepAwakeController

    init(app: DisplayCoordinator) {
        self.app = app
        self.featureController = KeepAwakeFeatureController()
        self.keepAwakeController = KeepAwakeController()
    }

    var isActive: Bool {
        keepAwakeController.isActive
    }

    func handleWakeEvent() {
        var state = app.keepAwakeState
        let shouldStartDefaultSession = featureController.handleWakeEvent(state: &state)
        app.keepAwakeState = state

        if shouldStartDefaultSession {
            startDefaultAfterWakeSession()
        }
    }

    func startDefaultAfterWakeSession() {
        startSessionWithDefault()
    }

    func setKeepAwakeFeatureEnabled(_ enabled: Bool) {
        var state = app.keepAwakeState
        featureController.setFeatureEnabled(enabled, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func toggleKeepAwake() {
        setKeepAwakeFeatureEnabled(!app.keepAwakeState.featureEnabled)
    }

    func setKeepAwakePluggedOnly(_ enabled: Bool) {
        var state = app.keepAwakeState
        featureController.setPluggedOnly(enabled, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func setKeepAwakeDisplayAwake(_ enabled: Bool) {
        var state = app.keepAwakeState
        featureController.setDisplayAwake(enabled, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func setKeepDisplayAwakeOnWake(_ enabled: Bool) {
        // Compatibility API: this setting controls the display assertion,
        // while featureEnabled controls the complete keep-awake feature.
        setKeepAwakeDisplayAwake(enabled)
    }

    func setKeepAwakeDefaultDurationMode(_ mode: String) {
        var state = app.keepAwakeState
        featureController.setDefaultDurationMode(mode, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func setKeepAwakeDefaultCustomMinutes(_ minutes: Int) {
        var state = app.keepAwakeState
        featureController.setDefaultCustomMinutes(minutes, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func startSessionWithDefault() {
        var state = app.keepAwakeState
        featureController.startDefaultSession(state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func startSessionWithDurationMode(_ mode: String) {
        var state = app.keepAwakeState
        featureController.startDurationMode(mode, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func startSessionWithCustomMinutes(_ minutes: Int) {
        var state = app.keepAwakeState
        featureController.startCustomMinutes(minutes, state: &state)
        app.keepAwakeState = state
        refreshKeepAwakeLifecycleIfNeeded()
    }

    func disableKeepAwake() {
        setKeepAwakeFeatureEnabled(false)
    }

    func setKeepAwakeDuration(_ duration: TimeInterval) {
        let minutes = Int(round(duration / 60.0))
        if minutes == 15 {
            startSessionWithDurationMode("15")
        } else if minutes == 30 {
            startSessionWithDurationMode("30")
        } else if minutes == 60 {
            startSessionWithDurationMode("60")
        } else {
            startSessionWithCustomMinutes(minutes)
        }
    }

    var keepAwakeSummaryText: String {
        app.keepAwakeState.featureEnabled ? keepAwakeStatusSummary() : "Kapalı"
    }

    var keepAwakePluggedOnlySummaryText: String {
        app.keepAwakeState.onlyWhilePluggedIn ? "Sadece fişteyken" : "Herhangi bir güçte"
    }

    var keepAwakeUntilText: String? {
        if !app.keepAwakeState.featureEnabled || !keepAwakeController.isActive { return nil }
        return app.remainingIdleTimeString
    }

    func refreshKeepAwakeLifecycleIfNeeded() {
        guard app.keepAwakeState.featureEnabled else {
            if keepAwakeController.isActive {
                keepAwakeController.stop()
                updateKeepAwakeStateIDs()
            }
            app.currentIdleTimeString = "00:00"
            app.remainingIdleTimeString = "--:--"
            updateKeepAwakeTitle()
            return
        }

        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            CGEventSourceStateID.hidSystemState,
            eventType: CGEventType(rawValue: ~0) ?? .null
        )

        let mode = app.keepAwakeState.temporaryOverrideActive ? (app.keepAwakeState.temporaryIdleTimeoutMode ?? "15") : app.keepAwakeState.defaultIdleTimeoutMode
        let customMins = app.keepAwakeState.temporaryOverrideActive ? app.keepAwakeState.temporaryIdleTimeoutMinutes : app.keepAwakeState.defaultIdleTimeoutMinutes

        var timeoutSeconds: TimeInterval = 0
        switch mode {
        case "15": timeoutSeconds = 15 * 60
        case "30": timeoutSeconds = 30 * 60
        case "60": timeoutSeconds = 60 * 60
        case "custom": timeoutSeconds = Double(customMins ?? 15) * 60
        case "never": timeoutSeconds = .infinity
        default: timeoutSeconds = 15 * 60
        }

        let isPluggedIn = isOnACPower()
        let powerConditionMet = !app.keepAwakeState.onlyWhilePluggedIn || isPluggedIn

        let shouldBeActive = powerConditionMet && (idleSeconds < timeoutSeconds)

        if shouldBeActive != keepAwakeController.isActive {
            let _ = keepAwakeController.syncAssertions(enabled: shouldBeActive, keepDisplayAwake: app.keepAwakeState.keepDisplayAwake)
            updateKeepAwakeStateIDs()
        }

        let idleInt = Int(idleSeconds)
        let mIdle = idleInt / 60
        let sIdle = idleInt % 60
        app.currentIdleTimeString = String(format: "%02d:%02d", mIdle, sIdle)

        if timeoutSeconds == .infinity {
            app.remainingIdleTimeString = "Süresiz"
        } else {
            let rem = max(0, Int(timeoutSeconds - idleSeconds))
            let mRem = rem / 60
            let sRem = rem % 60
            if shouldBeActive {
                app.remainingIdleTimeString = String(format: "Uykuya izin verilmesine: %02d:%02d", mRem, sRem)
            } else {
                app.remainingIdleTimeString = "Uykuya izin verildi"
            }
        }

        if !powerConditionMet && app.keepAwakeState.onlyWhilePluggedIn {
            app.remainingIdleTimeString = "Güç bekleniyor"
        }

        updateKeepAwakeTitle()
    }

    func stop() {
        keepAwakeController.stop()
    }

    private func updateKeepAwakeTitle() {
        app.setKeepAwakeMenuTitle(keepAwakeController.isActive ? "Ekran açık tutuluyor: \(keepAwakeStatusSummary())" : "Uyanık tut: Kapalı")
    }

    private func keepAwakeStatusSummary() -> String {
        guard app.keepAwakeState.featureEnabled else { return "Kapalı" }

        var summary = keepAwakeController.isActive ? "Uyanık" : "Beklemede"
        if app.keepAwakeState.onlyWhilePluggedIn {
            summary += isOnACPower() ? " (fişte)" : " (güç bekleniyor)"
        }

        summary += " · \(app.remainingIdleTimeString)"
        return summary
    }

    private func isOnACPower() -> Bool {
        app.powerSourceController.currentState() == .ac
    }

    private func updateKeepAwakeStateIDs() {
        var state = app.keepAwakeState
        state.idleSleepAssertionID = keepAwakeController.idleSleepAssertionID
        state.displaySleepAssertionID = keepAwakeController.displaySleepAssertionID
        app.keepAwakeState = state
    }
}
