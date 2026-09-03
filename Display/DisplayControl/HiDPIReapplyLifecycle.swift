import Foundation

struct HiDPIReapplyLifecycle: Equatable {
    enum WorkState: String, Equatable {
        case idle
        case scheduled
        case executing
    }

    /// `isListening` reflects a successfully registered callback, not merely
    /// that a registration attempt was requested.
    private(set) var isListening = false
    private(set) var isRegistrationInFlight = false
    private(set) var workState: WorkState = .idle
    private(set) var operationGeneration: UInt64 = 0
    private(set) var isApplyingMode = false

    var hasPendingWork: Bool {
        workState != .idle
    }

    mutating func start() -> Bool {
        guard !isListening, !isRegistrationInFlight else { return false }
        isRegistrationInFlight = true
        return true
    }

    mutating func registrationSucceeded() {
        isRegistrationInFlight = false
        isListening = true
    }

    mutating func registrationFailed() {
        isRegistrationInFlight = false
        isListening = false
        operationGeneration &+= 1
        workState = .idle
        isApplyingMode = false
    }

    mutating func stop() -> Bool {
        let wasListening = isListening
        isRegistrationInFlight = false
        operationGeneration &+= 1
        workState = .idle
        isApplyingMode = false
        return wasListening
    }

    mutating func removalSucceeded() {
        isListening = false
    }

    /// Keep the registered state after an OS removal failure. This prevents a
    /// later start from registering a duplicate callback while the old one is
    /// still live.
    mutating func removalFailed() {
        isListening = true
    }

    mutating func scheduleWork() -> Bool {
        guard isListening, workState != .executing else { return false }
        operationGeneration &+= 1
        workState = .scheduled
        return true
    }

    mutating func beginExecution(for generation: UInt64) -> Bool {
        guard isListening,
              workState == .scheduled,
              operationGeneration == generation else { return false }
        workState = .executing
        return true
    }

    mutating func completeWork(for generation: UInt64? = nil) {
        guard generation == nil || generation == operationGeneration else { return }
        workState = .idle
    }

    mutating func cancelWork(for generation: UInt64? = nil) {
        guard generation == nil || generation == operationGeneration else { return }
        operationGeneration &+= 1
        workState = .idle
    }

    func shouldScheduleFromReconfigurationCallback() -> Bool {
        isListening && workState != .executing && !isApplyingMode
    }

    mutating func beginApplyingMode() -> Bool {
        guard !isApplyingMode else { return false }
        isApplyingMode = true
        return true
    }

    mutating func endApplyingMode() {
        isApplyingMode = false
    }
}
