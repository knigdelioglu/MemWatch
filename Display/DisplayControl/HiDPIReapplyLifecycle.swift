import Foundation

struct HiDPIReapplyLifecycle: Equatable {
    /// `isListening` reflects a successfully registered callback, not merely
    /// that a registration attempt was requested.
    private(set) var isListening = false
    private(set) var isRegistrationInFlight = false
    private(set) var hasPendingWork = false

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
        hasPendingWork = false
    }

    mutating func stop() -> Bool {
        let wasListening = isListening
        isRegistrationInFlight = false
        hasPendingWork = false
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
        guard isListening else { return false }
        hasPendingWork = true
        return true
    }

    mutating func completeWork() {
        hasPendingWork = false
    }
}
