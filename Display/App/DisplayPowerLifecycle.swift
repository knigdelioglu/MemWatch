import CoreGraphics
import Foundation

enum DisplayPowerState: String, Equatable, Sendable {
    case active
    case screenSleeping
    case systemSleeping
    case waking
}

struct DisplayPowerLifecycleSnapshot: Equatable, Sendable {
    let state: DisplayPowerState
    let generation: UInt64
    let isHiDPIAllowed: Bool

    var isActive: Bool {
        state == .active
    }

    static let blocked = DisplayPowerLifecycleSnapshot(
        state: .systemSleeping,
        generation: 0,
        isHiDPIAllowed: false
    )
}

/// Main-actor-owned state machine for display work. The generation changes on
/// every sleep/wake boundary so completions from an older display epoch can
/// never publish into the current UI state.
struct DisplayPowerLifecycle: Equatable, Sendable {
    static let defaultWakeStabilization: TimeInterval = 5.0

    private(set) var state: DisplayPowerState = .active
    private(set) var generation: UInt64 = 0
    private(set) var wakeStabilizationDeadline: Date?

    var allowsDisplayOperations: Bool {
        state == .active
    }

    mutating func prepareForStart() {
        state = .active
        wakeStabilizationDeadline = nil
        generation &+= 1
    }

    mutating func enterScreenSleep() {
        guard state != .systemSleeping else { return }
        transition(to: .screenSleeping)
    }

    mutating func enterSystemSleep() {
        transition(to: .systemSleeping)
    }

    mutating func beginWaking(
        now: Date = Date(),
        stabilizationDuration: TimeInterval = DisplayPowerLifecycle.defaultWakeStabilization
    ) {
        transition(to: .waking)
        wakeStabilizationDeadline = now.addingTimeInterval(max(0, stabilizationDuration))
    }

    mutating func resetWakeStabilization(
        now: Date = Date(),
        stabilizationDuration: TimeInterval = DisplayPowerLifecycle.defaultWakeStabilization
    ) {
        guard state == .waking else {
            beginWaking(now: now, stabilizationDuration: stabilizationDuration)
            return
        }

        generation &+= 1
        wakeStabilizationDeadline = now.addingTimeInterval(max(0, stabilizationDuration))
    }

    mutating func activateIfReady(now: Date = Date()) -> Bool {
        guard state == .waking,
              let deadline = wakeStabilizationDeadline,
              now >= deadline else {
            return false
        }

        state = .active
        wakeStabilizationDeadline = nil
        generation &+= 1
        return true
    }

    func isWakeStabilized(at now: Date = Date()) -> Bool {
        guard state == .waking, let deadline = wakeStabilizationDeadline else { return false }
        return now >= deadline
    }

    func accepts(_ candidateGeneration: UInt64, requiringActive: Bool = true) -> Bool {
        guard candidateGeneration == generation else { return false }
        return !requiringActive || allowsDisplayOperations
    }

    func snapshot(isHiDPIAllowed: Bool) -> DisplayPowerLifecycleSnapshot {
        DisplayPowerLifecycleSnapshot(
            state: state,
            generation: generation,
            isHiDPIAllowed: isHiDPIAllowed && allowsDisplayOperations
        )
    }

    private mutating func transition(to nextState: DisplayPowerState) {
        if state != nextState {
            state = nextState
            generation &+= 1
        } else if nextState == .systemSleeping {
            // Repeated will-sleep notifications still invalidate in-flight
            // work even when AppKit delivers the same phase twice.
            generation &+= 1
        }

        if nextState != .waking {
            wakeStabilizationDeadline = nil
        }
    }
}

/// Synchronous boundary shared by the actor-backed DDC writer and the
/// main-actor private display controller. It closes the gap between a
/// coordinator guard and an actual Process.run/CGS call.
final class DisplayPowerOperationGate: @unchecked Sendable {
    static let shared = DisplayPowerOperationGate()

    private let lock = NSLock()
    private var allowed = true
    private var generation: UInt64 = 0

    func suspend() {
        lock.lock()
        allowed = false
        generation &+= 1
        lock.unlock()
    }

    func activate(generation: UInt64) {
        lock.lock()
        allowed = true
        self.generation = generation
        lock.unlock()
    }

    func isAllowed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed
    }

    func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func accepts(_ candidateGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed && generation == candidateGeneration
    }
}

struct TargetDisplayWakeCandidate: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let isOnline: Bool
    let isActive: Bool
}

enum TargetDisplayWakeStabilizationPolicy {
    static let confirmationNanoseconds: UInt64 = 750_000_000
    static let maxRetries: Int = 5

    static func isCandidateValid(
        initial: TargetDisplayWakeCandidate?,
        confirmed: TargetDisplayWakeCandidate?
    ) -> Bool {
        guard let initial, initial.isOnline, initial.isActive else { return false }
        guard let confirmed, confirmed.isOnline, confirmed.isActive else { return false }
        return initial.displayID == confirmed.displayID
    }

    static func shouldWaitForTarget(
        isTargetExpected: Bool,
        retryCount: Int
    ) -> Bool {
        isTargetExpected && retryCount < maxRetries
    }
}

