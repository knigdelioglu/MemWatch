import Foundation

enum MemoryAlertKind: String, Equatable {
    case activeSwap
    case memoryPressure
    case critical
    case recovered
}

struct MemoryAlertPayload: Equatable {
    let kind: MemoryAlertKind
    let title: String
    let body: String
}

struct NotificationPolicyConfiguration {
    var repeatCooldown: TimeInterval = 15 * 60
}

final class NotificationPolicyEngine {
    private let configuration: NotificationPolicyConfiguration
    private var lastObservedState: SwapHealthState = .stable
    private var lastAlertDateByState: [SwapHealthState: Date] = [:]
    private var hasIssuedActiveAlert = false

    init(configuration: NotificationPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    func evaluate(
        state: SwapHealthState,
        summary: String,
        now: Date = .now
    ) -> MemoryAlertPayload? {
        defer { lastObservedState = state }

        let previousState = lastObservedState
        let previousWasAlert = isAlertState(previousState)
        let currentIsAlert = isAlertState(state)

        if currentIsAlert {
            let stateChanged = state != previousState
            let escalation = severity(state) > severity(previousState)
            let cooldownExpired = shouldRepeat(state: state, now: now)

            let shouldNotify =
                !hasIssuedActiveAlert ||
                (stateChanged && escalation) ||
                cooldownExpired

            guard shouldNotify else { return nil }

            hasIssuedActiveAlert = true
            lastAlertDateByState[state] = now
            return alertPayload(for: state, summary: summary)
        }

        if hasIssuedActiveAlert && previousWasAlert {
            hasIssuedActiveAlert = false
            return MemoryAlertPayload(
                kind: .recovered,
                title: "Memory pressure recovered",
                body: "MemWatch no longer detects sustained swap pressure."
            )
        }

        return nil
    }

    func reset() {
        lastObservedState = .stable
        lastAlertDateByState.removeAll(keepingCapacity: true)
        hasIssuedActiveAlert = false
    }

    private func shouldRepeat(state: SwapHealthState, now: Date) -> Bool {
        guard let lastDate = lastAlertDateByState[state] else { return false }
        return now.timeIntervalSince(lastDate) >= max(configuration.repeatCooldown, 0)
    }

    private func alertPayload(
        for state: SwapHealthState,
        summary: String
    ) -> MemoryAlertPayload? {
        switch state {
        case .activeSwap:
            return MemoryAlertPayload(
                kind: .activeSwap,
                title: "Active swap detected",
                body: summary
            )
        case .pressure:
            return MemoryAlertPayload(
                kind: .memoryPressure,
                title: "Memory pressure is elevated",
                body: summary
            )
        case .critical:
            return MemoryAlertPayload(
                kind: .critical,
                title: "Critical memory pressure",
                body: summary
            )
        case .stable, .idleSwap, .readback:
            return nil
        }
    }

    private func isAlertState(_ state: SwapHealthState) -> Bool {
        severity(state) >= severity(.activeSwap)
    }

    private func severity(_ state: SwapHealthState) -> Int {
        switch state {
        case .stable: return 0
        case .idleSwap, .readback: return 1
        case .activeSwap: return 2
        case .pressure: return 3
        case .critical: return 4
        }
    }
}
