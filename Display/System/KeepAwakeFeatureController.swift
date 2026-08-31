import Foundation

final class KeepAwakeFeatureController {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func loadInitialState(defaults: UserDefaults = .standard) -> KeepAwakeState {
        if let data = defaults.data(forKey: "AmbientSync.KeepAwakeStateJSON"),
           var state = try? JSONDecoder().decode(KeepAwakeState.self, from: data) {
            state.temporaryIdleTimeoutMode = nil
            state.temporaryIdleTimeoutMinutes = nil
            state.temporaryOverrideActive = false
            state.idleSleepAssertionID = 0
            state.displaySleepAssertionID = 0
            state.lastStopReason = "none"
            return state
        }

        let plugged = defaults.bool(forKey: "AmbientSync.KeepAwakePluggedOnly")
        let featureEnabled = defaults.object(forKey: "AmbientSync.KeepDisplayAwakeOnWake") != nil
            ? defaults.bool(forKey: "AmbientSync.KeepDisplayAwakeOnWake")
            : true

        return KeepAwakeState(
            featureEnabled: featureEnabled,
            defaultIdleTimeoutMode: "15",
            defaultIdleTimeoutMinutes: 15,
            temporaryIdleTimeoutMode: nil,
            temporaryIdleTimeoutMinutes: nil,
            temporaryOverrideActive: false,
            onlyWhilePluggedIn: plugged,
            keepDisplayAwake: true,
            idleSleepAssertionID: 0,
            displaySleepAssertionID: 0,
            lastWakeTriggerAt: nil,
            lastStopReason: "none"
        )
    }

    func persistState(_ state: KeepAwakeState) {
        let persistentState = normalizedPersistenceState(state)

        if let data = try? JSONEncoder().encode(persistentState) {
            defaults.set(data, forKey: "AmbientSync.KeepAwakeStateJSON")
        }
    }

    func handleWakeEvent(state: inout KeepAwakeState, now: Date = Date()) -> Bool {
        if let lastWake = state.lastWakeTriggerAt, now.timeIntervalSince(lastWake) < 5.0 {
            return false
        }

        state.lastWakeTriggerAt = now
        persistState(state)
        return state.featureEnabled
    }

    func setFeatureEnabled(_ enabled: Bool, state: inout KeepAwakeState) {
        state.featureEnabled = enabled
        persistState(state)
    }

    func setPluggedOnly(_ enabled: Bool, state: inout KeepAwakeState) {
        state.onlyWhilePluggedIn = enabled
        persistState(state)
    }

    func setDisplayAwake(_ enabled: Bool, state: inout KeepAwakeState) {
        state.keepDisplayAwake = enabled
        persistState(state)
    }

    func setDefaultDurationMode(_ mode: String, state: inout KeepAwakeState) {
        state.defaultIdleTimeoutMode = mode
        persistState(state)
    }

    func setDefaultCustomMinutes(_ minutes: Int, state: inout KeepAwakeState) {
        state.defaultIdleTimeoutMinutes = minutes
        persistState(state)
    }

    func startDefaultSession(state: inout KeepAwakeState) {
        state.temporaryOverrideActive = false
        state.temporaryIdleTimeoutMode = nil
        state.temporaryIdleTimeoutMinutes = nil
    }

    func startDurationMode(_ mode: String, state: inout KeepAwakeState) {
        state.temporaryOverrideActive = true
        state.temporaryIdleTimeoutMode = mode
    }

    func startCustomMinutes(_ minutes: Int, state: inout KeepAwakeState) {
        state.temporaryOverrideActive = true
        state.temporaryIdleTimeoutMode = "custom"
        state.temporaryIdleTimeoutMinutes = minutes
    }

    func normalizedPersistenceState(_ state: KeepAwakeState) -> KeepAwakeState {
        var copy = state
        copy.temporaryIdleTimeoutMode = nil
        copy.temporaryIdleTimeoutMinutes = nil
        copy.temporaryOverrideActive = false
        copy.idleSleepAssertionID = 0
        copy.displaySleepAssertionID = 0
        return copy
    }
}
