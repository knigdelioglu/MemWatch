import Foundation

enum ThermalLifecycleEvent: Sendable, Equatable {
    case systemWillSleep
    case systemDidWake
}

enum ThermalLifecycleState: Sendable, Equatable {
    case active
    case suspended
}

enum BackendUnavailableReason: String, Sendable, Equatable, Hashable, Codable {
    case clientCreationFailed
    case copyServicesUnavailable
    case noUsableSensors
    case permissionDenied
    case sandboxRestricted
    case symbolUnavailable
    case runtimeTransportFailure
    case badSampleCoverage
    case rediscoveryFailed
    case invalidCoverage
    case lifecycleSuspended
}

enum BackendUnsupportedReason: String, Sendable, Equatable, Hashable, Codable {
    case backendUnsupported
    case platformUnsupported
    case decoderUnavailable
}

enum TemperatureBackendAvailability: Sendable, Equatable, Hashable, Codable {
    case available
    case degraded
    case unavailable(reason: BackendUnavailableReason)
    case unsupported(reason: BackendUnsupportedReason)

    var isSelectable: Bool {
        switch self {
        case .available, .degraded:
            return true
        case .unavailable, .unsupported:
            return false
        }
    }
}

struct BackendRuntimeHealth: Sendable, Equatable, Codable {
    let attemptedCount: Int
    let validCount: Int
    let failedCount: Int
    let invalidCount: Int
    let consecutiveBackendBadSamples: Int
    let rediscoveryAttempted: Bool

    init(
        attemptedCount: Int = 0,
        validCount: Int = 0,
        failedCount: Int = 0,
        invalidCount: Int = 0,
        consecutiveBackendBadSamples: Int = 0,
        rediscoveryAttempted: Bool = false
    ) {
        self.attemptedCount = attemptedCount
        self.validCount = validCount
        self.failedCount = failedCount
        self.invalidCount = invalidCount
        self.consecutiveBackendBadSamples = consecutiveBackendBadSamples
        self.rediscoveryAttempted = rediscoveryAttempted
    }

    static let empty = BackendRuntimeHealth()

    var validCoverage: Double? {
        guard attemptedCount > 0 else { return nil }
        return Double(validCount) / Double(attemptedCount)
    }

    var hasBadSampleCoverage: Bool {
        attemptedCount > 0 && validCount == 0 && failedCount + invalidCount >= attemptedCount
    }
}

struct TemperatureBackendStatus: Sendable, Equatable, Codable {
    let source: TemperatureSensorSource
    let availability: TemperatureBackendAvailability
    let runtimeHealth: BackendRuntimeHealth

    init(
        source: TemperatureSensorSource,
        availability: TemperatureBackendAvailability = .available,
        runtimeHealth: BackendRuntimeHealth = .empty
    ) {
        self.source = source
        self.availability = availability
        self.runtimeHealth = runtimeHealth
    }
}

typealias ThermalBackendStatuses = [TemperatureSensorSource: TemperatureBackendStatus]

struct TemperatureCollectionCoverage: Sendable, Equatable, Codable {
    let attemptedCount: Int
    let validCount: Int
    let failedCount: Int
    let invalidCount: Int
    let transportFailure: Bool

    init(
        attemptedCount: Int,
        validCount: Int,
        failedCount: Int,
        invalidCount: Int,
        transportFailure: Bool = false
    ) {
        self.attemptedCount = attemptedCount
        self.validCount = validCount
        self.failedCount = failedCount
        self.invalidCount = invalidCount
        self.transportFailure = transportFailure
    }

    var isConsistent: Bool {
        attemptedCount >= 0
            && validCount >= 0
            && failedCount >= 0
            && invalidCount >= 0
            && validCount + failedCount + invalidCount <= attemptedCount
    }

    var validCoverage: Double? {
        guard attemptedCount > 0 else { return nil }
        return Double(validCount) / Double(attemptedCount)
    }

    var hasAnyValidSample: Bool {
        validCount > 0
    }

    var isAllBad: Bool {
        attemptedCount > 0 && validCount == 0 && failedCount + invalidCount >= attemptedCount
    }
}

struct ThermalHealthConfiguration: Sendable, Equatable, Codable {
    let badSampleConsecutiveThreshold: Int
    let minimumAttemptsForBadCoverage: Int

    init(
        badSampleConsecutiveThreshold: Int = 3,
        minimumAttemptsForBadCoverage: Int = 2
    ) {
        self.badSampleConsecutiveThreshold = max(1, badSampleConsecutiveThreshold)
        self.minimumAttemptsForBadCoverage = max(1, minimumAttemptsForBadCoverage)
    }

    static let `default` = ThermalHealthConfiguration()
}

enum TemperatureDiscoveryFailure: String, Sendable, Equatable, Hashable, Codable {
    case clientCreationFailed
    case copyServicesUnavailable
    case noUsableSensors
    case permissionDenied
    case sandboxRestricted
    case symbolUnavailable
    case backendUnsupported
}

enum TemperatureDiscoveryEvent: Sendable, Equatable {
    case discovered(usableSensorCount: Int)
    case failed(reason: TemperatureDiscoveryFailure)
}

enum TemperatureDiscoveryState: Sendable, Equatable {
    case notAttempted
    case discovered(usableSensorCount: Int)
    case fallbackRequired(reason: TemperatureDiscoveryFailure)

    var requiresImmediateFallback: Bool {
        if case .fallbackRequired = self { return true }
        return false
    }
}

struct TemperatureDiscoveryStateMachine: Sendable, Equatable {
    let state: TemperatureDiscoveryState

    init(state: TemperatureDiscoveryState = .notAttempted) {
        self.state = state
    }

    func applying(_ event: TemperatureDiscoveryEvent) -> TemperatureDiscoveryState {
        Self.transition(from: state, event: event)
    }

    static func transition(
        from state: TemperatureDiscoveryState,
        event: TemperatureDiscoveryEvent
    ) -> TemperatureDiscoveryState {
        switch event {
        case let .discovered(usableSensorCount):
            guard usableSensorCount > 0 else {
                return .fallbackRequired(reason: .noUsableSensors)
            }
            return .discovered(usableSensorCount: usableSensorCount)
        case let .failed(reason):
            return .fallbackRequired(reason: reason)
        }
    }
}

enum TemperatureRuntimeFailureReason: Sendable, Equatable {
    case rediscoveryFailed(reason: TemperatureDiscoveryFailure)
    case noUsableSensors
    case transportFailure
    case invalidCoverage
}

enum TemperatureRuntimeState: Sendable, Equatable {
    case notSampled
    case healthy
    case degraded
    case badSampleCoverage(consecutiveCount: Int)
    case rediscoveryRequested
    case reselectRequired(reason: TemperatureRuntimeFailureReason)

    var requiresRediscovery: Bool {
        if case .rediscoveryRequested = self { return true }
        return false
    }

    var requiresSourcePolicyReevaluation: Bool {
        if case .reselectRequired = self { return true }
        return false
    }

    var isBackendBadSampleCandidate: Bool {
        switch self {
        case .badSampleCoverage, .rediscoveryRequested:
            return true
        case .notSampled, .healthy, .degraded, .reselectRequired:
            return false
        }
    }
}

enum TemperatureRuntimeEvent: Sendable, Equatable {
    case collection(TemperatureCollectionCoverage)
    case rediscoverySucceeded(usableSensorCount: Int)
    case rediscoveryFailed(reason: TemperatureDiscoveryFailure)
}

struct TemperatureRuntimeStateMachine: Sendable, Equatable {
    let state: TemperatureRuntimeState
    let configuration: ThermalHealthConfiguration

    init(
        state: TemperatureRuntimeState = .notSampled,
        configuration: ThermalHealthConfiguration = .default
    ) {
        self.state = state
        self.configuration = configuration
    }

    func applying(_ event: TemperatureRuntimeEvent) -> TemperatureRuntimeState {
        Self.transition(from: state, event: event, configuration: configuration)
    }

    static func transition(
        from state: TemperatureRuntimeState,
        event: TemperatureRuntimeEvent,
        configuration: ThermalHealthConfiguration = .default
    ) -> TemperatureRuntimeState {
        switch event {
        case let .collection(coverage):
            guard coverage.isConsistent else { return .reselectRequired(reason: .invalidCoverage) }
            guard !coverage.transportFailure else { return .rediscoveryRequested }
            guard coverage.attemptedCount > 0 else { return .notSampled }

            if coverage.validCount == coverage.attemptedCount {
                return .healthy
            }
            if coverage.hasAnyValidSample {
                return .degraded
            }
            guard coverage.attemptedCount >= configuration.minimumAttemptsForBadCoverage else {
                return .degraded
            }
            guard coverage.isAllBad else { return .degraded }

            let previousCount: Int
            if case let .badSampleCoverage(consecutiveCount) = state {
                previousCount = consecutiveCount
            } else {
                previousCount = 0
            }
            let nextCount = previousCount + 1
            if nextCount >= configuration.badSampleConsecutiveThreshold {
                return .rediscoveryRequested
            }
            return .badSampleCoverage(consecutiveCount: nextCount)

        case let .rediscoverySucceeded(usableSensorCount):
            guard usableSensorCount > 0 else {
                return .reselectRequired(reason: .noUsableSensors)
            }
            return .healthy

        case let .rediscoveryFailed(reason):
            return .reselectRequired(reason: .rediscoveryFailed(reason: reason))
        }
    }
}

struct TemperatureBackendHealthAssessment: Sendable, Equatable {
    let availability: TemperatureBackendAvailability
    let runtimeHealth: BackendRuntimeHealth
    let runtimeState: TemperatureRuntimeState
    let sourcePolicyReevaluationRequired: Bool
}

struct TemperatureBackendHealthClassifier: Sendable {
    let configuration: ThermalHealthConfiguration

    init(configuration: ThermalHealthConfiguration = .default) {
        self.configuration = configuration
    }

    func classify(
        coverage: TemperatureCollectionCoverage,
        previousRuntimeHealth: BackendRuntimeHealth = .empty,
        rediscoveryAttempted: Bool = false
    ) -> TemperatureBackendHealthAssessment {
        let previousState: TemperatureRuntimeState = previousRuntimeHealth.consecutiveBackendBadSamples > 0
            ? .badSampleCoverage(consecutiveCount: previousRuntimeHealth.consecutiveBackendBadSamples)
            : .healthy
        let runtimeState = TemperatureRuntimeStateMachine.transition(
            from: previousState,
            event: .collection(coverage),
            configuration: configuration
        )

        let consecutiveBadSamples: Int
        if case let .badSampleCoverage(count) = runtimeState {
            consecutiveBadSamples = count
        } else if runtimeState.requiresRediscovery {
            consecutiveBadSamples = max(
                configuration.badSampleConsecutiveThreshold,
                previousRuntimeHealth.consecutiveBackendBadSamples + 1
            )
        } else {
            consecutiveBadSamples = 0
        }

        let runtimeHealth = BackendRuntimeHealth(
            attemptedCount: coverage.attemptedCount,
            validCount: coverage.validCount,
            failedCount: coverage.failedCount,
            invalidCount: coverage.invalidCount,
            consecutiveBackendBadSamples: consecutiveBadSamples,
            rediscoveryAttempted: rediscoveryAttempted
        )

        let availability: TemperatureBackendAvailability
        if !coverage.isConsistent {
            availability = .unavailable(reason: .invalidCoverage)
        } else if coverage.transportFailure {
            availability = .unavailable(reason: .runtimeTransportFailure)
        } else if case .reselectRequired = runtimeState {
            availability = .unavailable(reason: .rediscoveryFailed)
        } else if coverage.attemptedCount > 0,
                  coverage.validCount == coverage.attemptedCount {
            availability = .available
        } else {
            availability = .degraded
        }

        return TemperatureBackendHealthAssessment(
            availability: availability,
            runtimeHealth: runtimeHealth,
            runtimeState: runtimeState,
            sourcePolicyReevaluationRequired: !availability.isSelectable
                || runtimeState.requiresSourcePolicyReevaluation
        )
    }

    func discoveryFailureStatus(
        source: TemperatureSensorSource,
        failure: TemperatureDiscoveryFailure
    ) -> TemperatureBackendStatus {
        let availability: TemperatureBackendAvailability
        switch failure {
        case .backendUnsupported:
            availability = .unsupported(reason: .backendUnsupported)
        case .clientCreationFailed:
            availability = .unavailable(reason: .clientCreationFailed)
        case .copyServicesUnavailable:
            availability = .unavailable(reason: .copyServicesUnavailable)
        case .noUsableSensors:
            availability = .unavailable(reason: .noUsableSensors)
        case .permissionDenied:
            availability = .unavailable(reason: .permissionDenied)
        case .sandboxRestricted:
            availability = .unavailable(reason: .sandboxRestricted)
        case .symbolUnavailable:
            availability = .unavailable(reason: .symbolUnavailable)
        }
        return TemperatureBackendStatus(source: source, availability: availability)
    }
}

enum TemperatureCategoryUnavailableReason: String, Sendable, Equatable, Hashable, Codable {
    case noCanonicalSource
    case backendUnavailable
    case noValidSamples
    case epochMismatch
    case rediscoveryRequired
    case lifecycleSuspended
}

enum TemperatureCategoryAvailability: Sendable, Equatable, Hashable, Codable {
    case available
    case degraded
    case temporarilyUnavailable(reason: TemperatureCategoryUnavailableReason)
    case unmapped
    case notSampled
}

struct ThermalCategoryAvailabilityReport: Sendable, Equatable {
    let statuses: [TemperatureSensorCategory: TemperatureCategoryAvailability]

    init(statuses: [TemperatureSensorCategory: TemperatureCategoryAvailability] = [:]) {
        self.statuses = statuses
    }

    init(_ statuses: [TemperatureSensorCategory: TemperatureCategoryAvailability]) {
        self.init(statuses: statuses)
    }

    static let empty = ThermalCategoryAvailabilityReport()

    func status(for category: TemperatureSensorCategory) -> TemperatureCategoryAvailability {
        statuses[category] ?? .notSampled
    }

    func hasExplicitStatus(for category: TemperatureSensorCategory) -> Bool {
        statuses[category] != nil
    }

    var all: [TemperatureSensorCategory: TemperatureCategoryAvailability] {
        statuses
    }
}

struct TemperatureCategoryHealthClassifier: Sendable {
    static func classify(
        category: TemperatureSensorCategory,
        readings: [TemperatureSensorReading],
        selection: TemperatureCategorySourceSelection?,
        hardwareEpoch: UInt64
    ) -> TemperatureCategoryAvailability {
        guard let selection, let source = selection.source else {
            let hasMappedReading = readings.contains {
                $0.mapping.category == category && $0.mapping.status == .mapped
            }
            return hasMappedReading ? .temporarilyUnavailable(reason: .noCanonicalSource) : .unmapped
        }

        let relevant = readings.filter {
            $0.identity.source == source
                && $0.mapping.category == category
                && $0.mapping.status == .mapped
                && $0.hardwareEpoch == hardwareEpoch
        }
        guard !relevant.isEmpty else {
            let sameSourceAndCategory = readings.contains {
                $0.identity.source == source
                    && $0.mapping.category == category
                    && $0.mapping.status == .mapped
            }
            return sameSourceAndCategory
                ? .temporarilyUnavailable(reason: .epochMismatch)
                : .notSampled
        }

        let validCount = relevant.reduce(into: 0) { count, reading in
            if let celsius = reading.sample.validCelsius,
               TemperatureValidator.isValid(celsius) {
                count += 1
            }
        }
        guard validCount > 0 else {
            return .temporarilyUnavailable(reason: .noValidSamples)
        }
        return validCount == relevant.count ? .available : .degraded
    }
}
