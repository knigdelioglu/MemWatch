import Foundation

private struct FakeSensorPlan {
    let rawIdentifier: String
    let mapping: SensorMapping
    let sample: TemperatureSample

    init(
        rawIdentifier: String,
        mapping: SensorMapping,
        sample: TemperatureSample
    ) {
        self.rawIdentifier = rawIdentifier
        self.mapping = mapping
        self.sample = sample
    }
}

private struct FakeBatchPlan {
    let sensors: [FakeSensorPlan]
    let discoveryFailure: TemperatureDiscoveryFailure?
    let forcedEpoch: UInt64?

    init(
        sensors: [FakeSensorPlan],
        discoveryFailure: TemperatureDiscoveryFailure? = nil,
        forcedEpoch: UInt64? = nil
    ) {
        self.sensors = sensors
        self.discoveryFailure = discoveryFailure
        self.forcedEpoch = forcedEpoch
    }
}

private final class ScriptedHIDTemperatureSource: HIDTemperatureSampling {
    private let plans: [FakeBatchPlan]
    private(set) var sampleCount = 0
    private(set) var invalidateCount = 0

    init(plans: [FakeBatchPlan]) {
        precondition(!plans.isEmpty, "A scripted source needs at least one plan")
        self.plans = plans
    }

    func sample(timestamp: Date, hardwareEpoch: UInt64) -> HIDTemperatureSampleBatch {
        let plan = plans[min(sampleCount, plans.count - 1)]
        sampleCount += 1

        let resultEpoch = plan.forcedEpoch ?? hardwareEpoch
        let readings = plan.sensors.map { sensor in
            TemperatureSensorReading(
                identity: SensorIdentity(
                    source: .ioHID,
                    rawIdentifier: sensor.rawIdentifier,
                    rawName: sensor.rawIdentifier
                ),
                mapping: sensor.mapping,
                sample: sensor.sample,
                timestamp: timestamp,
                hardwareEpoch: resultEpoch
            )
        }
        let discoveredSensors = plan.sensors.map { sensor in
            HIDDiscoveredTemperatureSensor(
                identity: SensorIdentity(
                    source: .ioHID,
                    rawIdentifier: sensor.rawIdentifier,
                    rawName: sensor.rawIdentifier
                ),
                mapping: sensor.mapping,
                rawProperties: [:]
            )
        }

        let coverage: TemperatureCollectionCoverage
        if plan.discoveryFailure != nil {
            coverage = TemperatureCollectionCoverage(
                attemptedCount: 0,
                validCount: 0,
                failedCount: 0,
                invalidCount: 0,
                transportFailure: true
            )
        } else {
            var validCount = 0
            var failedCount = 0
            var invalidCount = 0
            for sensor in plan.sensors {
                switch sensor.sample.status {
                case .valid:
                    validCount += 1
                case .readFailed:
                    failedCount += 1
                case .invalidSample, .stale, .notSampled:
                    invalidCount += 1
                }
            }
            coverage = TemperatureCollectionCoverage(
                attemptedCount: plan.sensors.count,
                validCount: validCount,
                failedCount: failedCount,
                invalidCount: invalidCount
            )
        }

        let discovery: HIDTemperatureDiscovery
        let backendStatus: TemperatureBackendStatus
        if let failure = plan.discoveryFailure {
            discovery = HIDTemperatureDiscovery(
                sensors: [],
                availability: TemperatureBackendHealthClassifier().discoveryFailureStatus(
                    source: .ioHID,
                    failure: failure
                ).availability,
                failure: failure,
                failureDescription: "fixture discovery failure"
            )
            backendStatus = TemperatureBackendHealthClassifier().discoveryFailureStatus(
                source: .ioHID,
                failure: failure
            )
        } else {
            discovery = HIDTemperatureDiscovery(
                sensors: discoveredSensors,
                availability: .available,
                failure: nil,
                failureDescription: nil
            )
            backendStatus = TemperatureBackendStatus(source: .ioHID)
        }

        return HIDTemperatureSampleBatch(
            timestamp: timestamp,
            hardwareEpoch: resultEpoch,
            readings: readings,
            coverage: coverage,
            backendStatus: backendStatus,
            discovery: discovery,
            failure: plan.discoveryFailure
        )
    }

    func invalidate() {
        invalidateCount += 1
    }
}

@main
struct ThermalCollectorTests {
    static func main() async {
        testConsecutiveBadSamplesPersistAndRecoverOnce()
        testDiscoveryFailureIsImmediateAndCached()
        testMixedAndUnknownReadingsPreserveCanonicalData()
        testEpochInvalidationChangesCollectionEpoch()
        testOldEpochBatchIsRejectedSafely()
        await testMonitoringCollectorIntegratesThermalOnce()
        print("PASS ThermalCollector integration and recovery")
    }

    private static func testConsecutiveBadSamplesPersistAndRecoverOnce() {
        let source = ScriptedHIDTemperatureSource(plans: [
            allBadPlan(),
            allBadPlan(),
            allBadPlan(),
            validStoragePlan(celsius: 43),
            validStoragePlan(celsius: 44)
        ])
        let collector = ThermalCollector(hidSource: source)

        let first = collector.collect(at: timestamp(1))
        let second = collector.collect(at: timestamp(2))
        let recovered = collector.collect(at: timestamp(3))
        let next = collector.collect(at: timestamp(4))

        require(first.hardwareEpoch == 1 && second.hardwareEpoch == 1, "Bad samples must stay in the original epoch")
        require(first.backendStatuses[.ioHID]?.runtimeHealth.consecutiveBackendBadSamples == 1, "First bad sample must be remembered")
        require(second.backendStatuses[.ioHID]?.runtimeHealth.consecutiveBackendBadSamples == 2, "Second bad sample must accumulate in ThermalCollector")
        require(source.invalidateCount == 1, "The threshold must trigger one invalidation")
        require(source.sampleCount == 5, "Recovery must make exactly one bounded rediscovery sample")
        require(recovered.hardwareEpoch == 2 && next.hardwareEpoch == 2, "Recovery must create a new hardware epoch")
        require(recovered.backendStatuses[.ioHID]?.availability == .available, "Successful rediscovery must restore backend selection")
        require(recovered.backendStatuses[.ioHID]?.runtimeHealth.consecutiveBackendBadSamples == 0, "Recovery must reset bad-sample count")
        require(recovered.backendStatuses[.ioHID]?.runtimeHealth.rediscoveryAttempted == true, "Recovery attempt must remain visible in runtime health")
        require(recovered.categorySourceSelections.source(for: .storage) == .ioHID, "Recovered storage source must be selected by policy")
        require(recovered.aggregates[.storage]?.currentCelsius == 43, "Recovered storage reading must aggregate")
        require(next.backendStatuses[.ioHID]?.runtimeHealth.consecutiveBackendBadSamples == 0, "Healthy post-recovery sample must stay healthy")
        require(next.categorySourceSelections.source(for: .storage) == .ioHID, "Stable source must remain selected")
        require(collector.selectionGeneration == recovered.categorySourceSelections[.storage]?.selectionGeneration, "Stable source must not increment generation on every sample")
    }

    private static func testDiscoveryFailureIsImmediateAndCached() {
        let source = ScriptedHIDTemperatureSource(plans: [
            FakeBatchPlan(sensors: [], discoveryFailure: .sandboxRestricted)
        ])
        let collector = ThermalCollector(hidSource: source)

        let first = collector.collect(at: timestamp(10))
        let second = collector.collect(at: timestamp(11))

        require(first.backendStatuses[.ioHID]?.availability == .unavailable(reason: .sandboxRestricted), "Discovery failure must be immediately unavailable")
        require(first.categorySourceSelections.source(for: .storage) == nil, "Unavailable HID must not select storage")
        require(first.categorySourceSelections.source(for: .battery) == nil, "Unavailable HID must not select battery")
        require(first.readings.isEmpty, "Discovery failure must not fabricate readings")
        require(second.backendStatuses[.ioHID] == first.backendStatuses[.ioHID], "Capability failure must remain visible")
        require(source.sampleCount == 1, "Cached capability failure must not retry on every collection")

        collector.invalidateHardware(reason: .explicitReset)
        _ = collector.collect(at: timestamp(12))
        require(source.invalidateCount == 1, "Explicit invalidation must be the retry boundary")
        require(source.sampleCount == 2, "Explicit invalidation must permit one new discovery attempt")
    }

    private static func testMixedAndUnknownReadingsPreserveCanonicalData() {
        let unknown = (0..<45).map { index in
            FakeSensorPlan(
                rawIdentifier: "unknown-\(index)",
                mapping: SensorMapping(status: .unmapped, category: .unknown),
                sample: .valid(celsius: 30 + Double(index) / 10)
            )
        }
        let source = ScriptedHIDTemperatureSource(plans: [
            FakeBatchPlan(sensors: [
                FakeSensorPlan(
                    rawIdentifier: "NAND CH0 temp",
                    mapping: storageMapping,
                    sample: .valid(celsius: 41)
                ),
                FakeSensorPlan(
                    rawIdentifier: "failed-sensor",
                    mapping: SensorMapping(status: .unmapped, category: .unknown),
                    sample: .readFailed(code: "fixture read failure")
                )
            ] + unknown)
        ])
        let snapshot = ThermalCollector(hidSource: source).collect(at: timestamp(20))

        require(snapshot.readings.count == 47, "Raw mixed readings must be preserved")
        require(snapshot.readings.contains { $0.identity.rawIdentifier == "failed-sensor" && $0.status == .readFailed }, "Failed raw sensor must remain visible")
        require(snapshot.readings.contains { $0.identity.rawIdentifier == "unknown-0" && $0.mapping.status == .unmapped }, "Unknown raw sensor must remain visible")
        require(snapshot.backendStatuses[.ioHID]?.availability == .degraded, "One failed sensor must only degrade the backend")
        require(snapshot.categorySourceSelections.source(for: .storage) == .ioHID, "One failed sensor must not switch the canonical source")
        require(snapshot.categorySourceSelections.source(for: .cpu) == nil, "HID storage data must not be promoted to CPU")
        require(snapshot.categorySourceSelections.source(for: .gpu) == nil, "HID storage data must not be promoted to GPU")
        require(snapshot.categorySourceSelections.source(for: .memory) == nil, "HID storage data must not be promoted to memory")
        require(snapshot.backendStatuses[.appleSMC]?.availability == .unsupported(reason: .backendUnsupported), "AppleSMC must remain explicitly unsupported")
        require(snapshot.aggregates[.storage]?.currentCelsius == 41, "Valid canonical storage data must aggregate")
        require(snapshot.aggregates[.cpu] == nil, "Unknown/PMU-like data must not create a CPU aggregate")
        require(source.invalidateCount == 0, "Partial coverage must not trigger invalidation")
    }

    private static func testEpochInvalidationChangesCollectionEpoch() {
        let source = ScriptedHIDTemperatureSource(plans: [validStoragePlan(celsius: 37)])
        let collector = ThermalCollector(hidSource: source)

        let first = collector.collect(at: timestamp(30))
        collector.invalidateHardware(reason: .systemWake)
        let second = collector.collect(at: timestamp(31))

        require(first.hardwareEpoch == 1, "Initial collection must use epoch one")
        require(collector.hardwareEpoch == 2 && second.hardwareEpoch == 2, "Invalidation must advance the sole hardware epoch owner")
        require(second.readings.allSatisfy { $0.hardwareEpoch == 2 }, "Post-invalidation readings must use the new epoch")
        require(second.aggregates[.storage]?.hardwareEpoch == 2, "Post-invalidation aggregates must use the new epoch")
        require(source.invalidateCount == 1, "Invalidation must reach the HID source")
    }

    private static func testOldEpochBatchIsRejectedSafely() {
        let source = ScriptedHIDTemperatureSource(plans: [
            FakeBatchPlan(
                sensors: [FakeSensorPlan(rawIdentifier: "old", mapping: storageMapping, sample: .valid(celsius: 99))],
                forcedEpoch: 0
            )
        ])
        let snapshot = ThermalCollector(hidSource: source).collect(at: timestamp(40))

        require(snapshot.readings.isEmpty, "A source batch from an old epoch must not be committed")
        require(snapshot.aggregates[.storage] == nil, "A source batch from an old epoch must not aggregate")
        require(snapshot.backendStatuses[.ioHID]?.availability == .unavailable(reason: .runtimeTransportFailure), "Epoch mismatch must remain an unavailable thermal result")
    }

    private static func testMonitoringCollectorIntegratesThermalOnce() async {
        let source = ScriptedHIDTemperatureSource(plans: [validStoragePlan(celsius: 39)])
        let thermalCollector = ThermalCollector(hidSource: source)
        let worker = MonitoringCollector(thermalCollector: thermalCollector)
        let snapshot = await worker.collect(
            MonitoringCollectionRequest(includeProcesses: false, includeStorage: true)
        )

        require(snapshot.thermal.hardwareEpoch == 1, "Monitoring snapshot must carry thermal epoch")
        require(snapshot.thermal.readings.count == 1, "Monitoring snapshot must carry thermal readings")
        require(snapshot.thermal.aggregates[.storage]?.currentCelsius == 39, "Monitoring snapshot must carry thermal aggregate")
        require(snapshot.storageVolumes != nil, "Existing storage collection must remain available")
        require(snapshot.memory.totalBytes > 0, "Memory collection must remain available with thermal collection")
        require(snapshot.power.timestamp != .distantPast, "Power collection must remain available with thermal collection")
        require(source.sampleCount == 1, "Thermal source must be sampled exactly once per worker collection")
    }

    private static let storageMapping = SensorMapping(
        status: .mapped,
        catalogID: "iohid.storage.nand-ch0",
        category: .storage,
        confidence: .high,
        aggregationGroup: "internal-storage",
        aggregationRole: .canonicalStorage
    )

    private static func allBadPlan() -> FakeBatchPlan {
        let sensors = [
            FakeSensorPlan(
                rawIdentifier: "NAND CH0 temp",
                mapping: storageMapping,
                sample: .invalidSample(reason: "fixture invalid")
            )
        ] + (0..<46).map { index in
            FakeSensorPlan(
                rawIdentifier: "bad-\(index)",
                mapping: SensorMapping(status: .unmapped, category: .unknown),
                sample: .readFailed(code: "fixture failure")
            )
        }
        return FakeBatchPlan(sensors: sensors)
    }

    private static func validStoragePlan(celsius: Double) -> FakeBatchPlan {
        FakeBatchPlan(sensors: [
            FakeSensorPlan(
                rawIdentifier: "NAND CH0 temp",
                mapping: storageMapping,
                sample: .valid(celsius: celsius)
            )
        ])
    }

    private static func timestamp(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
