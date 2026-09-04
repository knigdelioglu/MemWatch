import Foundation

/// Reasons are intentionally thermal-only. System lifecycle invalidation is
/// forwarded here by MonitoringService; this remains the only hardware epoch
/// owner.
enum ThermalInvalidationReason: Sendable, Equatable {
    case systemSleep
    case systemWake
    case backendRecovery
    case explicitReset
}

/// The source is deliberately synchronous and non-Sendable. ThermalCollector
/// is only used from the serialized MonitoringCollector actor, so no nested
/// actor hop or unchecked Sendable promise is needed.
protocol HIDTemperatureSampling: AnyObject {
    func sample(timestamp: Date, hardwareEpoch: UInt64) -> HIDTemperatureSampleBatch
    func invalidate()
}

extension HIDTemperatureSource: HIDTemperatureSampling {}

/// Stateful thermal orchestration owned by MonitoringCollector's actor
/// confinement. This is a class rather than an actor so the existing worker
/// remains the only serialization boundary for hardware collection.
final class ThermalCollector {
    private struct HIDCollectionResult {
        let epoch: UInt64
        let readings: [TemperatureSensorReading]
        let status: TemperatureBackendStatus
    }

    private static let unsupportedAppleSMCStatus = TemperatureBackendStatus(
        source: .appleSMC,
        availability: .unsupported(reason: .backendUnsupported)
    )

    private let hidSource: any HIDTemperatureSampling
    private let catalog: SensorCatalog
    private let sourcePolicy: ThermalSourcePolicy
    private let aggregator: ThermalAggregator
    private let healthClassifier: TemperatureBackendHealthClassifier

    // Thermal hardware epoch has one owner. MonitoringService and
    // HIDTemperatureSource intentionally do not keep or advance this value.
    private(set) var hardwareEpoch: UInt64 = 1
    private(set) var lifecycleState: ThermalLifecycleState = .active
    private(set) var selectionGeneration: UInt64 = 0
    private(set) var latestSourceSelections = ThermalCategorySourceSelections.empty
    private(set) var latestBackendStatuses: ThermalBackendStatuses = [
        .appleSMC: unsupportedAppleSMCStatus
    ]
    private(set) var latestCategoryAvailability = ThermalCategoryAvailabilityReport.empty

    private var hidDiscoveryState = TemperatureDiscoveryState.notAttempted
    private var hidRuntimeState = TemperatureRuntimeState.notSampled
    private var previousHIDRuntimeHealth = BackendRuntimeHealth.empty
    private var rediscoveryAttemptsInEpoch = 0
    private let maximumRediscoveryAttemptsPerEpoch = 1
    private var cachedHIDUnavailableStatus: TemperatureBackendStatus?

    init(
        hidSource: (any HIDTemperatureSampling)? = nil,
        catalog: SensorCatalog = .initial,
        sourcePolicy: ThermalSourcePolicy = ThermalSourcePolicy(),
        aggregator: ThermalAggregator = ThermalAggregator(),
        healthConfiguration: ThermalHealthConfiguration = .default
    ) {
        self.catalog = catalog
        self.sourcePolicy = sourcePolicy
        self.aggregator = aggregator
        self.healthClassifier = TemperatureBackendHealthClassifier(configuration: healthConfiguration)
        self.hidSource = hidSource ?? HIDTemperatureSource(catalog: catalog)
    }

    /// Collects one immutable thermal snapshot. The caller already provides
    /// serialization, so this method intentionally has no async abstraction.
    func collect(at timestamp: Date = Date()) -> ThermalSnapshot {
        guard lifecycleState == .active else {
            return suspendedSnapshot(at: timestamp)
        }

        let collection = collectHID(at: timestamp)

        // A source must never commit readings obtained for another hardware
        // epoch. This is defensive today and protects the future lifecycle
        // boundary from stale aggregate reuse.
        guard collection.epoch == hardwareEpoch else {
            return staleSnapshot(at: timestamp)
        }

        let backendStatuses = [
            TemperatureSensorSource.ioHID: collection.status,
            TemperatureSensorSource.appleSMC: Self.unsupportedAppleSMCStatus
        ]

        // First select from backend capability and catalog semantics. A first
        // valid batch must be allowed to establish a canonical selection
        // before category health is used to reject an unavailable category.
        let initialDecision = sourcePolicy.evaluate(
            backendStatuses: backendStatuses,
            catalog: catalog,
            currentSelections: latestSourceSelections,
            selectionGeneration: selectionGeneration
        )
        let initialAvailability = categoryAvailability(
            for: collection.readings,
            selections: initialDecision.selections,
            hardwareEpoch: hardwareEpoch
        )

        // Re-evaluate with current category health. This keeps source policy
        // as the sole owner of canonical source choice while allowing a
        // category with no current valid reading to become unavailable.
        let finalDecision = sourcePolicy.evaluate(
            backendStatuses: backendStatuses,
            catalog: catalog,
            categoryAvailability: initialAvailability,
            currentSelections: latestSourceSelections,
            selectionGeneration: selectionGeneration
        )
        let finalAvailability = categoryAvailability(
            for: collection.readings,
            selections: finalDecision.selections,
            hardwareEpoch: hardwareEpoch
        )

        selectionGeneration = finalDecision.selectionGeneration
        latestSourceSelections = finalDecision.selections
        latestBackendStatuses = backendStatuses
        latestCategoryAvailability = finalAvailability

        return ThermalSnapshot(
            timestamp: timestamp,
            hardwareEpoch: hardwareEpoch,
            backendStatuses: backendStatuses,
            categorySourceSelections: finalDecision.selections,
            categoryAvailability: finalAvailability,
            aggregates: aggregator.aggregate(
                readings: collection.readings,
                selections: finalDecision.selections,
                hardwareEpoch: hardwareEpoch
            ),
            readings: collection.readings
        )
    }

    /// System sleep and wake are explicit thermal boundaries. Wake advances
    /// the epoch defensively even when the process did not observe the sleep
    /// notification, so no pre-wake hardware reference can be reused.
    func handleLifecycleEvent(_ event: ThermalLifecycleEvent) {
        switch event {
        case .systemWillSleep:
            guard lifecycleState != .suspended else { return }
            invalidateHardware(reason: .systemSleep)
        case .systemDidWake:
            invalidateHardware(reason: .systemWake)
        }
    }

    /// Invalidates all source-owned hardware references and starts a new
    /// thermal hardware epoch. The next collection performs lazy discovery.
    func invalidateHardware(reason: ThermalInvalidationReason) {
        hardwareEpoch &+= 1
        hidSource.invalidate()

        switch reason {
        case .systemSleep:
            lifecycleState = .suspended
        case .systemWake, .backendRecovery, .explicitReset:
            lifecycleState = .active
        }

        hidDiscoveryState = .notAttempted
        hidRuntimeState = .notSampled
        previousHIDRuntimeHealth = .empty
        rediscoveryAttemptsInEpoch = 0
        cachedHIDUnavailableStatus = nil

        // Keep the generation monotonic; clearing the actual selections makes
        // the next canonical choice receive a new generation from policy.
        latestSourceSelections = .empty
        latestBackendStatuses = [.appleSMC: Self.unsupportedAppleSMCStatus]
        latestCategoryAvailability = .empty
    }

    private func suspendedSnapshot(at timestamp: Date) -> ThermalSnapshot {
        let backendStatuses = [
            TemperatureSensorSource.ioHID: TemperatureBackendStatus(
                source: .ioHID,
                availability: .unavailable(reason: .lifecycleSuspended)
            ),
            TemperatureSensorSource.appleSMC: Self.unsupportedAppleSMCStatus
        ]
        let categoryAvailability = ThermalCategoryAvailabilityReport(
            statuses: Dictionary(
                uniqueKeysWithValues: TemperatureSensorCategory.allCases.map {
                    ($0, .temporarilyUnavailable(reason: .lifecycleSuspended))
                }
            )
        )

        latestSourceSelections = .empty
        latestBackendStatuses = backendStatuses
        latestCategoryAvailability = categoryAvailability

        return ThermalSnapshot(
            timestamp: timestamp,
            hardwareEpoch: hardwareEpoch,
            backendStatuses: backendStatuses,
            categorySourceSelections: .empty,
            categoryAvailability: categoryAvailability,
            aggregates: .empty,
            readings: []
        )
    }

    private func collectHID(at timestamp: Date) -> HIDCollectionResult {
        if let cachedHIDUnavailableStatus {
            return HIDCollectionResult(
                epoch: hardwareEpoch,
                readings: [],
                status: cachedHIDUnavailableStatus
            )
        }

        let collectionEpoch = hardwareEpoch
        let batch = hidSource.sample(
            timestamp: timestamp,
            hardwareEpoch: collectionEpoch
        )

        guard batch.hardwareEpoch == collectionEpoch else {
            hidRuntimeState = .reselectRequired(reason: .transportFailure)
            return HIDCollectionResult(
                epoch: batch.hardwareEpoch,
                readings: [],
                status: TemperatureBackendStatus(
                    source: .ioHID,
                    availability: .unavailable(reason: .runtimeTransportFailure)
                )
            )
        }

        if let failure = discoveryFailure(in: batch) {
            return cacheInitialDiscoveryFailure(failure)
        }

        hidDiscoveryState = TemperatureDiscoveryStateMachine.transition(
            from: hidDiscoveryState,
            event: .discovered(usableSensorCount: batch.discovery.sensors.count)
        )

        let assessment = healthClassifier.classify(
            coverage: batch.coverage,
            previousRuntimeHealth: previousHIDRuntimeHealth,
            rediscoveryAttempted: rediscoveryAttemptsInEpoch > 0
        )
        previousHIDRuntimeHealth = assessment.runtimeHealth
        hidRuntimeState = assessment.runtimeState

        if assessment.runtimeState.requiresRediscovery {
            if rediscoveryAttemptsInEpoch >= maximumRediscoveryAttemptsPerEpoch {
                return cacheExhaustedRecovery(
                    health: assessment.runtimeHealth
                )
            }
            return attemptRediscovery(at: timestamp)
        }

        return HIDCollectionResult(
            epoch: collectionEpoch,
            readings: batch.readings,
            status: TemperatureBackendStatus(
                source: .ioHID,
                availability: assessment.availability,
                runtimeHealth: assessment.runtimeHealth
            )
        )
    }

    private func attemptRediscovery(at timestamp: Date) -> HIDCollectionResult {
        // Invalidation increments the epoch and clears the recovery budget;
        // consume the single attempt after that reset so it cannot loop.
        invalidateHardware(reason: .backendRecovery)
        rediscoveryAttemptsInEpoch = 1

        let recoveryEpoch = hardwareEpoch
        let batch = hidSource.sample(
            timestamp: timestamp,
            hardwareEpoch: recoveryEpoch
        )

        guard batch.hardwareEpoch == recoveryEpoch else {
            hidRuntimeState = .reselectRequired(reason: .transportFailure)
            return HIDCollectionResult(
                epoch: batch.hardwareEpoch,
                readings: [],
                status: TemperatureBackendStatus(
                    source: .ioHID,
                    availability: .unavailable(reason: .runtimeTransportFailure),
                    runtimeHealth: BackendRuntimeHealth(rediscoveryAttempted: true)
                )
            )
        }

        if let failure = discoveryFailure(in: batch) {
            return cacheRediscoveryFailure(failure)
        }

        hidDiscoveryState = TemperatureDiscoveryStateMachine.transition(
            from: hidDiscoveryState,
            event: .discovered(usableSensorCount: batch.discovery.sensors.count)
        )

        let coverage = batch.coverage
        let recoveredHealth = BackendRuntimeHealth(
            attemptedCount: coverage.attemptedCount,
            validCount: coverage.validCount,
            failedCount: coverage.failedCount,
            invalidCount: coverage.invalidCount,
            consecutiveBackendBadSamples: 0,
            rediscoveryAttempted: true
        )
        previousHIDRuntimeHealth = recoveredHealth
        // A successful discovery resets the consecutive bad-sample counter.
        // The current sample can still be degraded without causing another
        // immediate rediscovery in this hardware epoch.
        hidRuntimeState = TemperatureRuntimeStateMachine.transition(
            from: hidRuntimeState,
            event: .rediscoverySucceeded(usableSensorCount: batch.discovery.sensors.count),
            configuration: healthClassifier.configuration
        )

        let availability: TemperatureBackendAvailability
        if !coverage.isConsistent {
            availability = .unavailable(reason: .invalidCoverage)
            hidRuntimeState = .reselectRequired(reason: .invalidCoverage)
        } else if coverage.transportFailure {
            availability = .unavailable(reason: .runtimeTransportFailure)
            hidRuntimeState = .reselectRequired(reason: .transportFailure)
        } else if coverage.attemptedCount > 0,
                  coverage.validCount == coverage.attemptedCount {
            availability = .available
        } else {
            availability = .degraded
        }

        return HIDCollectionResult(
            epoch: recoveryEpoch,
            readings: batch.readings,
            status: TemperatureBackendStatus(
                source: .ioHID,
                availability: availability,
                runtimeHealth: recoveredHealth
            )
        )
    }

    private func cacheInitialDiscoveryFailure(
        _ failure: TemperatureDiscoveryFailure
    ) -> HIDCollectionResult {
        hidDiscoveryState = TemperatureDiscoveryStateMachine.transition(
            from: hidDiscoveryState,
            event: .failed(reason: failure)
        )
        hidRuntimeState = TemperatureRuntimeStateMachine.transition(
            from: hidRuntimeState,
            event: .rediscoveryFailed(reason: failure),
            configuration: healthClassifier.configuration
        )
        previousHIDRuntimeHealth = .empty

        let status = healthClassifier.discoveryFailureStatus(
            source: .ioHID,
            failure: failure
        )
        cachedHIDUnavailableStatus = status
        return HIDCollectionResult(
            epoch: hardwareEpoch,
            readings: [],
            status: status
        )
    }

    private func cacheRediscoveryFailure(
        _ failure: TemperatureDiscoveryFailure
    ) -> HIDCollectionResult {
        hidDiscoveryState = TemperatureDiscoveryStateMachine.transition(
            from: hidDiscoveryState,
            event: .failed(reason: failure)
        )
        hidRuntimeState = TemperatureRuntimeStateMachine.transition(
            from: hidRuntimeState,
            event: .rediscoveryFailed(reason: failure),
            configuration: healthClassifier.configuration
        )
        previousHIDRuntimeHealth = BackendRuntimeHealth(rediscoveryAttempted: true)

        let status = TemperatureBackendStatus(
            source: .ioHID,
            availability: .unavailable(reason: .rediscoveryFailed),
            runtimeHealth: previousHIDRuntimeHealth
        )
        cachedHIDUnavailableStatus = status
        return HIDCollectionResult(
            epoch: hardwareEpoch,
            readings: [],
            status: status
        )
    }

    private func cacheExhaustedRecovery(
        health: BackendRuntimeHealth
    ) -> HIDCollectionResult {
        hidRuntimeState = TemperatureRuntimeStateMachine.transition(
            from: hidRuntimeState,
            event: .rediscoveryFailed(reason: .noUsableSensors),
            configuration: healthClassifier.configuration
        )
        let status = TemperatureBackendStatus(
            source: .ioHID,
            availability: .unavailable(reason: .rediscoveryFailed),
            runtimeHealth: BackendRuntimeHealth(
                attemptedCount: health.attemptedCount,
                validCount: health.validCount,
                failedCount: health.failedCount,
                invalidCount: health.invalidCount,
                consecutiveBackendBadSamples: health.consecutiveBackendBadSamples,
                rediscoveryAttempted: true
            )
        )
        cachedHIDUnavailableStatus = status
        return HIDCollectionResult(
            epoch: hardwareEpoch,
            readings: [],
            status: status
        )
    }

    private func discoveryFailure(
        in batch: HIDTemperatureSampleBatch
    ) -> TemperatureDiscoveryFailure? {
        if let failure = batch.failure ?? batch.discovery.failure {
            return failure
        }
        return batch.discovery.isSuccessful ? nil : .noUsableSensors
    }

    private func categoryAvailability(
        for readings: [TemperatureSensorReading],
        selections: ThermalCategorySourceSelections,
        hardwareEpoch: UInt64
    ) -> ThermalCategoryAvailabilityReport {
        ThermalCategoryAvailabilityReport(
            statuses: Dictionary(
                uniqueKeysWithValues: TemperatureSensorCategory.allCases.map { category in
                    (
                        category,
                        TemperatureCategoryHealthClassifier.classify(
                            category: category,
                            readings: readings,
                            selection: selections[category],
                            hardwareEpoch: hardwareEpoch
                        )
                    )
                }
            )
        )
    }

    private func staleSnapshot(at timestamp: Date) -> ThermalSnapshot {
        let staleStatuses = Dictionary(
            uniqueKeysWithValues: TemperatureSensorCategory.allCases.map {
                ($0, TemperatureCategoryAvailability.temporarilyUnavailable(reason: .epochMismatch))
            }
        )
        let backendStatuses = [
            TemperatureSensorSource.ioHID: TemperatureBackendStatus(
                source: .ioHID,
                availability: .unavailable(reason: .runtimeTransportFailure)
            ),
            TemperatureSensorSource.appleSMC: Self.unsupportedAppleSMCStatus
        ]
        latestSourceSelections = .empty
        latestBackendStatuses = backendStatuses
        latestCategoryAvailability = ThermalCategoryAvailabilityReport(statuses: staleStatuses)
        return ThermalSnapshot(
            timestamp: timestamp,
            hardwareEpoch: hardwareEpoch,
            backendStatuses: backendStatuses,
            categorySourceSelections: .empty,
            categoryAvailability: latestCategoryAvailability,
            aggregates: .empty,
            readings: []
        )
    }
}
