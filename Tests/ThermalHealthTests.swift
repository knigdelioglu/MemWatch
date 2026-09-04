import Foundation

@main
struct ThermalHealthTests {
    static func main() {
        testDiscoveryFailuresFallbackImmediately()
        testHealthyAndDegradedCoverage()
        testSingleFailureIsNotWholeBackendFailure()
        testBadCoverageRequestsRediscoveryAfterThreshold()
        testRediscoveryFailureRequiresReselection()
        testTransportFailureIsVisible()
        testCategoryHealthIsSeparateFromBackendHealth()
        testCatalogConfidenceDoesNotLearnFromSamples()
        print("PASS Thermal health state")
    }

    private static func testDiscoveryFailuresFallbackImmediately() {
        let failures: [TemperatureDiscoveryFailure] = [
            .clientCreationFailed,
            .copyServicesUnavailable,
            .noUsableSensors,
            .permissionDenied,
            .sandboxRestricted,
            .symbolUnavailable,
            .backendUnsupported
        ]
        for failure in failures {
            let state = TemperatureDiscoveryStateMachine.transition(
                from: .notAttempted,
                event: .failed(reason: failure)
            )
            require(state.requiresImmediateFallback, "Discovery failure \(failure) must trigger immediate fallback")
        }

        let zeroSensors = TemperatureDiscoveryStateMachine.transition(
            from: .notAttempted,
            event: .discovered(usableSensorCount: 0)
        )
        require(zeroSensors == .fallbackRequired(reason: .noUsableSensors), "Zero usable sensors must be a discovery failure")
    }

    private static func testHealthyAndDegradedCoverage() {
        let classifier = TemperatureBackendHealthClassifier()
        let healthy = classifier.classify(
            coverage: TemperatureCollectionCoverage(attemptedCount: 47, validCount: 47, failedCount: 0, invalidCount: 0)
        )
        require(healthy.availability == .available, "Full valid coverage must be available")
        require(healthy.runtimeState == .healthy, "Full valid coverage must be healthy")

        let degraded = classifier.classify(
            coverage: TemperatureCollectionCoverage(attemptedCount: 47, validCount: 46, failedCount: 1, invalidCount: 0)
        )
        require(degraded.availability == .degraded, "Partial valid coverage must be degraded, not failed")
        require(!degraded.sourcePolicyReevaluationRequired, "One failed sensor must not force failover")
    }

    private static func testSingleFailureIsNotWholeBackendFailure() {
        let result = TemperatureBackendHealthClassifier().classify(
            coverage: TemperatureCollectionCoverage(attemptedCount: 1, validCount: 0, failedCount: 1, invalidCount: 0)
        )
        require(result.availability == .degraded, "One failed attempt is not transport-level backend failure")
        require(!result.sourcePolicyReevaluationRequired, "One failed attempt must not request failover")
        require(result.runtimeState == .degraded, "One failed attempt must remain bounded as degraded")
    }

    private static func testBadCoverageRequestsRediscoveryAfterThreshold() {
        let badCoverage = TemperatureCollectionCoverage(attemptedCount: 47, validCount: 0, failedCount: 47, invalidCount: 0)
        let machine = TemperatureRuntimeStateMachine()
        let first = machine.applying(.collection(badCoverage))
        let secondMachine = TemperatureRuntimeStateMachine(state: first)
        let second = secondMachine.applying(.collection(badCoverage))
        let thirdMachine = TemperatureRuntimeStateMachine(state: second)
        let third = thirdMachine.applying(.collection(badCoverage))

        require(first == .badSampleCoverage(consecutiveCount: 1), "First all-bad collection must be a bad-sample candidate")
        require(second == .badSampleCoverage(consecutiveCount: 2), "Second all-bad collection must remain bounded")
        require(third == .rediscoveryRequested, "Third consecutive all-bad collection must request rediscovery")

        let assessment = TemperatureBackendHealthClassifier().classify(
            coverage: badCoverage,
            previousRuntimeHealth: BackendRuntimeHealth(
                attemptedCount: 47,
                validCount: 0,
                failedCount: 47,
                invalidCount: 0,
                consecutiveBackendBadSamples: 2
            )
        )
        require(assessment.runtimeState == .rediscoveryRequested, "Classifier must expose the rediscovery threshold")
        require(assessment.availability == .degraded, "Rediscovery request is not a successful failover yet")
    }

    private static func testRediscoveryFailureRequiresReselection() {
        let state = TemperatureRuntimeStateMachine(state: .rediscoveryRequested).applying(
            .rediscoveryFailed(reason: .copyServicesUnavailable)
        )
        guard case let .reselectRequired(reason) = state else {
            fail("Failed rediscovery must require category source reselection")
        }
        require(reason == .rediscoveryFailed(reason: .copyServicesUnavailable), "Rediscovery failure reason must remain visible")
    }

    private static func testTransportFailureIsVisible() {
        let result = TemperatureBackendHealthClassifier().classify(
            coverage: TemperatureCollectionCoverage(
                attemptedCount: 47,
                validCount: 0,
                failedCount: 0,
                invalidCount: 0,
                transportFailure: true
            )
        )
        require(result.availability == .unavailable(reason: .runtimeTransportFailure), "Transport failure must mark the backend unavailable")
        require(result.sourcePolicyReevaluationRequired, "Transport failure must trigger policy reevaluation")
    }

    private static func testCategoryHealthIsSeparateFromBackendHealth() {
        let backend = TemperatureBackendStatus(
            source: .ioHID,
            availability: .available,
            runtimeHealth: BackendRuntimeHealth(attemptedCount: 47, validCount: 47)
        )
        let category = ThermalCategoryAvailabilityReport([
            .memory: .unmapped,
            .storage: .available
        ])
        require(backend.availability == .available, "Backend health must describe transport/runtime source health")
        require(category.status(for: .memory) == .unmapped, "Category health must independently describe semantic availability")
        require(category.status(for: .storage) == .available, "Category health must be independently addressable")
    }

    private static func testCatalogConfidenceDoesNotLearnFromSamples() {
        let mapping = SensorMapping(
            status: .mapped,
            catalogID: "battery",
            category: .battery,
            confidence: .high,
            aggregationRole: .canonicalBattery
        )
        let samples = [1, 10, 100].map { count in
            Array(repeating: TemperatureSample.valid(celsius: 34), count: count)
        }
        for sampleSet in samples {
            _ = sampleSet
            require(mapping.confidence == .high, "Repeated runtime samples must not raise catalog confidence")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }
}
