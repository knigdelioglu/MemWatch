import Darwin
import Foundation

private final class FakeHIDClient {}

private final class FakeHIDService {
    let id: String

    init(id: String) {
        self.id = id
    }
}

private final class FakeHIDEvent {
    let value: Double

    init(value: Double) {
        self.value = value
    }
}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?
}

private final class FakeHIDTemperatureAPI: HIDTemperatureAPI {
    struct ServiceSpec {
        let id: String
        let properties: [String: Any]
        let eventAvailable: Bool
        let eventValue: Double
        let registryMetadata: HIDRegistryMetadata?

        init(
            id: String,
            properties: [String: Any],
            eventAvailable: Bool = true,
            eventValue: Double = 42,
            registryMetadata: HIDRegistryMetadata? = nil
        ) {
            self.id = id
            self.properties = properties
            self.eventAvailable = eventAvailable
            self.eventValue = eventValue
            self.registryMetadata = registryMetadata
        }
    }

    var symbolAvailability: HIDTemperatureSymbolAvailability
    var serviceSpecs: [ServiceSpec]
    var createClientReturnsNil = false
    var copyServicesReturnsNil = false
    var setMatchingResult: Int32 = 0

    private(set) var resolveSymbolsCount = 0
    private(set) var createClientCount = 0
    private(set) var setMatchingCount = 0
    private(set) var copyServicesCount = 0
    private(set) var copyPropertyCount = 0
    private(set) var copyEventCount = 0
    private(set) var getFloatValueCount = 0
    private(set) var registryMetadataCount = 0
    private(set) var resetMetadataCacheCount = 0
    private(set) var lastMatchingPage: Int32?
    private(set) var lastMatchingUsage: Int32?
    weak var lastClient: FakeHIDClient?
    weak var lastService: FakeHIDService?

    init(
        serviceSpecs: [ServiceSpec] = [],
        symbolAvailability: HIDTemperatureSymbolAvailability = FakeHIDTemperatureAPI.availableSymbols
    ) {
        self.serviceSpecs = serviceSpecs
        self.symbolAvailability = symbolAvailability
    }

    static var availableSymbols: HIDTemperatureSymbolAvailability {
        HIDTemperatureSymbolAvailability(
            libraryPath: "fake://IOKit",
            libraryLoaded: true,
            symbols: Dictionary(uniqueKeysWithValues: HIDTemperatureSourceConstants.requiredSymbolNames.map { ($0, true) }),
            missingSymbols: []
        )
    }

    func resolveSymbols() -> HIDTemperatureSymbolAvailability {
        resolveSymbolsCount += 1
        return symbolAvailability
    }

    func createClient() -> AnyObject? {
        createClientCount += 1
        guard !createClientReturnsNil else { return nil }
        let client = FakeHIDClient()
        lastClient = client
        return client
    }

    @discardableResult
    func setMatching(
        _ client: AnyObject,
        primaryUsagePage: Int32,
        primaryUsage: Int32
    ) -> Int32 {
        setMatchingCount += 1
        lastMatchingPage = primaryUsagePage
        lastMatchingUsage = primaryUsage
        return setMatchingResult
    }

    func copyServices(_ client: AnyObject) -> [AnyObject]? {
        copyServicesCount += 1
        guard !copyServicesReturnsNil else { return nil }
        return serviceSpecs.map { spec in
            let service = FakeHIDService(id: spec.id)
            lastService = service
            return service
        }
    }

    func copyProperty(_ service: AnyObject, key: String) -> Any? {
        copyPropertyCount += 1
        guard let service = service as? FakeHIDService,
              let spec = serviceSpecs.first(where: { $0.id == service.id }) else {
            return nil
        }
        return spec.properties[key]
    }

    func copyEvent(
        _ service: AnyObject,
        eventType: Int64,
        options: Int32,
        matching: Int64
    ) -> AnyObject? {
        copyEventCount += 1
        guard let service = service as? FakeHIDService,
              let spec = serviceSpecs.first(where: { $0.id == service.id }),
              spec.eventAvailable else {
            return nil
        }
        return FakeHIDEvent(value: spec.eventValue)
    }

    func getFloatValue(_ event: AnyObject, field: Int32) -> Double {
        getFloatValueCount += 1
        return (event as! FakeHIDEvent).value
    }

    func registryMetadata(product: String?, locationID: String?) -> HIDRegistryMetadata? {
        registryMetadataCount += 1
        return serviceSpecs.first { spec in
            guard let metadata = spec.registryMetadata else { return false }
            let specProduct = spec.properties["Product"] as? String
            let specLocation = (spec.properties["LocationID"] as? NSNumber).map { $0.stringValue }
                ?? spec.properties["LocationID"] as? String
            return specProduct == product
                && specLocation == locationID
                && metadata.serviceClass != nil
        }?.registryMetadata
    }

    func resetMetadataCache() {
        resetMetadataCacheCount += 1
    }
}

@main
struct HIDTemperatureSourceTests {
    static func main() throws {
        if CommandLine.arguments.contains("--real-hardware-smoke") {
            runRealHardwareSmoke()
            return
        }

        try testProductionReadOnlyContract()
        testDiscoveryAndCatalogMapping()
        testOptionalPropertiesDoNotBlockDiscovery()
        testDiscoveryFailuresAreExplicitAndCached()
        testDiscoveryAndServiceReferencesAreCached()
        testSamplingQualityAndEpoch()
        testRuntimeReadsDoNotPromoteConfidence()
        print("PASS HID temperature source")
    }

    private static func testProductionReadOnlyContract() throws {
        let source = try String(
            contentsOfFile: "Collectors/HIDTemperatureSource.swift",
            encoding: .utf8
        )
        for symbol in HIDTemperatureSourceConstants.requiredSymbolNames {
            require(source.contains(symbol), "production HID source must reference \(symbol)")
        }
        require(source.contains("dlopen"), "production HID source must load IOKit dynamically")
        require(source.contains("dlsym"), "production HID source must resolve private symbols dynamically")
        require(source.contains("IORegistryEntryCreateCFProperties"), "source must use native read-only registry properties")
        require(source.contains("IORegistryEntryGetRegistryEntryID"), "source must attempt a native registry identity")
        require(source.contains("CFTypeRef, CFDictionary) -> Int32"), "source must use the validated Int32 matching ABI")
        require(source.contains("primaryUsagePage: Int32 = 0xFF00"), "source must use the validated vendor usage page")
        require(source.contains("primaryUsage: Int32 = 0x0005"), "source must use the validated temperature usage")
        require(source.contains("temperatureEventType: Int64 = 15"), "source must use the validated temperature event type")
        require(source.contains("temperatureEventFieldBase"), "source must use the validated temperature event field")
        require(source.contains("TemperatureValidator.validate"), "source must reuse the Phase 1 validator")
        require(source.contains("IOHIDEventSystemClientCreate"), "source must use the full event-system client")
        require(!source.contains("IOHIDEventSystemClientCreateSimpleClient"), "source must not use SimpleClient")
        require(!source.contains("SetMatchingMultiple"), "source must not use experimental multi-matching")

        let forbiddenTokens = [
            "IOHIDDeviceSetReport",
            "IOHIDServiceClientSetProperty",
            "IOHIDEventSystemClientSetProperty",
            "write",
            "fan",
            "voltage",
            "sudo",
            "Authorization Services",
            "privileged helper",
            "powermetrics",
            "Process("
        ]
        for token in forbiddenTokens {
            require(!source.localizedCaseInsensitiveContains(token), "production HID source contains forbidden token: \(token)")
        }
    }

    private static func testDiscoveryAndCatalogMapping() {
        let specs = [
            FakeHIDTemperatureAPI.ServiceSpec(
                id: "storage",
                properties: properties(product: "NAND CH0 temp", locationID: 101),
                registryMetadata: HIDRegistryMetadata(
                    serviceClass: "AppleEmbeddedNVMeTemperatureSensor",
                    registryEntryID: 9001,
                    registryName: "NAND CH0 temp",
                    modelIdentifier: nil
                )
            ),
            FakeHIDTemperatureAPI.ServiceSpec(
                id: "pmu",
                properties: properties(product: "PMU tdie1", locationID: 102),
                registryMetadata: HIDRegistryMetadata(
                    serviceClass: "AppleARMPMUTempSensor",
                    registryEntryID: 9002,
                    registryName: "PMU tdie1",
                    modelIdentifier: nil
                )
            ),
            FakeHIDTemperatureAPI.ServiceSpec(
                id: "unknown",
                properties: properties(product: "random thermal sensor", locationID: 103)
            )
        ]
        let api = FakeHIDTemperatureAPI(serviceSpecs: specs)
        // The target ABI may leave an arbitrary value in the return register;
        // discovery must rely on CopyServices rather than interpreting it.
        api.setMatchingResult = 93_454_800
        let source = HIDTemperatureSource(api: api)
        require(api.resolveSymbolsCount == 0, "source construction must not resolve symbols or touch hardware")
        let discovery = source.discover()

        require(discovery.isSuccessful, "three matched services must produce an available discovery")
        require(discovery.sensors.count == 3, "all matched services must be preserved")
        require(source.cachedSensorCount == 3, "all matched services must be cached")
        require(api.createClientCount == 1 && api.setMatchingCount == 1 && api.copyServicesCount == 1, "discovery must create/configure/copy exactly once")
        require(api.lastMatchingPage == HIDTemperatureSourceConstants.primaryUsagePage, "matching page must be FF00")
        require(api.lastMatchingUsage == HIDTemperatureSourceConstants.primaryUsage, "matching usage must be 5")

        let storage = discovery.sensors[0]
        require(storage.identity.serviceClass == "AppleEmbeddedNVMeTemperatureSensor", "registry class must be carried into identity")
        require(storage.mapping.category == .storage, "NAND storage identity must map through SensorCatalog")
        require(storage.mapping.confidence == .high, "NAND storage mapping must remain high confidence")
        require(storage.mapping.aggregationRole == .canonicalStorage, "NAND storage must remain canonical storage")
        require(storage.identity.rawIdentifier == "IORegistryEntryID=9001", "registry identity must be deterministic")

        let pmu = discovery.sensors[1]
        require(pmu.mapping.category == .pmu, "PMU tdie must map to PMU context")
        require(pmu.mapping.aggregationRole == .contextOnly, "PMU must remain context-only")
        require(pmu.mapping.category != .gpu, "PMU2/PMU-like names must not become GPU semantics in source")

        let unknown = discovery.sensors[2]
        require(unknown.mapping.status == .unmapped, "unknown sensors must remain unmapped, not be discarded")
        require(unknown.identity.rawName == "random thermal sensor", "unknown raw product must survive discovery")
    }

    private static func testOptionalPropertiesDoNotBlockDiscovery() {
        let api = FakeHIDTemperatureAPI(serviceSpecs: [
            FakeHIDTemperatureAPI.ServiceSpec(
                id: "minimal",
                properties: ["Product": "minimal thermal service"],
                eventValue: 43
            )
        ])
        let discovery = HIDTemperatureSource(api: api).discover()
        require(discovery.isSuccessful, "missing optional metadata must not block discovery")
        require(discovery.sensors.count == 1, "minimal service must be retained")
        require(discovery.sensors[0].identity.rawName == "minimal thermal service", "available Product must remain in identity")
        require(discovery.sensors[0].identity.serviceClass == nil, "missing service class must remain unknown")
        require(discovery.sensors[0].identity.rawIdentifier == "epoch-local-index=0", "index fallback must disclose epoch-local identity")
        require(discovery.sensors[0].mapping.status == .unmapped, "minimal unknown service must remain unmapped")
    }

    private static func testDiscoveryFailuresAreExplicitAndCached() {
        let missing = HIDTemperatureSymbolAvailability(
            libraryPath: "fake://IOKit",
            libraryLoaded: true,
            symbols: ["IOHIDEventSystemClientCreate": false],
            missingSymbols: ["IOHIDEventSystemClientCreate"]
        )
        let missingAPI = FakeHIDTemperatureAPI(symbolAvailability: missing)
        let missingSource = HIDTemperatureSource(api: missingAPI)
        let missingResult = missingSource.discover()
        require(missingResult.failure == .symbolUnavailable, "missing symbols must be explicit")
        require(missingResult.availability == .unavailable(reason: .symbolUnavailable), "missing symbols must be unavailable")
        require(missingAPI.createClientCount == 0, "symbol failure must not create a client")
        _ = missingSource.discover()
        require(missingAPI.resolveSymbolsCount == 1, "failed discovery must be cached until invalidation")

        let noClientAPI = FakeHIDTemperatureAPI()
        noClientAPI.createClientReturnsNil = true
        let noClient = HIDTemperatureSource(api: noClientAPI).discover()
        require(noClient.failure == .clientCreationFailed, "client creation failure must be explicit")
        require(noClient.availability == .unavailable(reason: .clientCreationFailed), "client creation failure must map to unavailable")

        let nilServicesAPI = FakeHIDTemperatureAPI()
        nilServicesAPI.copyServicesReturnsNil = true
        let nilServices = HIDTemperatureSource(api: nilServicesAPI).discover()
        require(nilServices.failure == .copyServicesUnavailable, "nil CopyServices must be explicit")

        let emptyServices = HIDTemperatureSource(api: FakeHIDTemperatureAPI()).discover()
        require(emptyServices.failure == .noUsableSensors, "empty services must be an explicit no-sensor failure")
    }

    private static func testDiscoveryAndServiceReferencesAreCached() {
        let api = FakeHIDTemperatureAPI(serviceSpecs: [
            FakeHIDTemperatureAPI.ServiceSpec(id: "one", properties: properties(product: "sensor one", locationID: 1), eventValue: 41),
            FakeHIDTemperatureAPI.ServiceSpec(id: "two", properties: properties(product: "sensor two", locationID: 2), eventValue: 42),
            FakeHIDTemperatureAPI.ServiceSpec(id: "three", properties: properties(product: "sensor three", locationID: 3), eventValue: 43)
        ])
        let source = HIDTemperatureSource(api: api)
        _ = source.discover()
        let firstClient = WeakReference<FakeHIDClient>()
        firstClient.value = api.lastClient
        let firstService = WeakReference<FakeHIDService>()
        firstService.value = api.lastService

        for index in 0..<10 {
            let batch = source.sample(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                hardwareEpoch: UInt64(index)
            )
            require(batch.readings.count == 3, "cached sample must read every cached service")
        }
        require(api.resolveSymbolsCount == 1, "cached samples must not resolve symbols again")
        require(api.createClientCount == 1, "cached samples must not create a client again")
        require(api.setMatchingCount == 1, "cached samples must not set matching again")
        require(api.copyServicesCount == 1, "cached samples must not rediscover services")
        require(api.copyEventCount == 30, "ten samples of three services must perform thirty event reads")

        source.invalidate()
        require(!source.hasDiscoveryCache && source.cachedSensorCount == 0, "invalidate must clear discovery and service cache")
        require(firstClient.value == nil, "invalidate must release the client")
        require(firstService.value == nil, "invalidate must release cached service references")

        _ = source.sample(timestamp: Date(), hardwareEpoch: 99)
        require(api.createClientCount == 2 && api.setMatchingCount == 2 && api.copyServicesCount == 2, "next sample after invalidate must rediscover exactly once")
        require(api.copyEventCount == 33, "the post-invalidation sample must add three event reads")
        require(api.resetMetadataCacheCount == 1, "invalidate must reset native metadata cache")
    }

    private static func testSamplingQualityAndEpoch() {
        let api = FakeHIDTemperatureAPI(serviceSpecs: [
            FakeHIDTemperatureAPI.ServiceSpec(id: "valid", properties: properties(product: "valid", locationID: 1), eventValue: 42.5),
            FakeHIDTemperatureAPI.ServiceSpec(id: "nan", properties: properties(product: "nan", locationID: 2), eventValue: .nan),
            FakeHIDTemperatureAPI.ServiceSpec(id: "infinity", properties: properties(product: "infinity", locationID: 3), eventValue: .infinity),
            FakeHIDTemperatureAPI.ServiceSpec(id: "out-of-range", properties: properties(product: "out-of-range", locationID: 4), eventValue: 180),
            FakeHIDTemperatureAPI.ServiceSpec(id: "zero", properties: properties(product: "zero", locationID: 5), eventValue: 0),
            FakeHIDTemperatureAPI.ServiceSpec(id: "missing-event", properties: properties(product: "missing-event", locationID: 6), eventAvailable: false)
        ])
        let source = HIDTemperatureSource(api: api)
        let batch = source.sample(
            timestamp: Date(timeIntervalSince1970: 42),
            hardwareEpoch: 42
        )

        require(batch.readings.count == 6, "a failed sensor must not remove other readings")
        require(batch.readings[0].sample == .valid(celsius: 42.5), "finite in-range value must be valid")
        require(batch.readings[1].sample.status == .invalidSample, "NaN must be invalid")
        require(batch.readings[2].sample.status == .invalidSample, "Infinity must be invalid")
        require(batch.readings[3].sample.status == .invalidSample, "out-of-range value must be invalid through validator")
        require(batch.readings[4].sample == .valid(celsius: 0), "zero Celsius must remain valid")
        require(batch.readings[5].sample.status == .readFailed, "missing event must remain readFailed")
        require(batch.coverage == TemperatureCollectionCoverage(attemptedCount: 6, validCount: 2, failedCount: 1, invalidCount: 3), "coverage must preserve valid/failed/invalid counts")
        require(batch.backendStatus.availability == .degraded, "partial invalid/read failure coverage must be degraded")
        require(batch.readings.allSatisfy { $0.hardwareEpoch == 42 }, "source must copy the caller's hardware epoch exactly")
        require(batch.readings.allSatisfy { $0.timestamp == Date(timeIntervalSince1970: 42) }, "source must copy the caller's timestamp exactly")
    }

    private static func testRuntimeReadsDoNotPromoteConfidence() {
        let api = FakeHIDTemperatureAPI(serviceSpecs: [
            FakeHIDTemperatureAPI.ServiceSpec(
                id: "storage",
                properties: properties(product: "NAND CH0 temp", locationID: 77),
                eventValue: 44,
                registryMetadata: HIDRegistryMetadata(
                    serviceClass: "AppleEmbeddedNVMeTemperatureSensor",
                    registryEntryID: 7001,
                    registryName: nil,
                    modelIdentifier: nil
                )
            )
        ])
        let source = HIDTemperatureSource(api: api)
        let initial = source.discover().sensors[0].mapping
        for index in 0..<100 {
            let batch = source.sample(timestamp: Date(timeIntervalSince1970: Double(index)), hardwareEpoch: 7)
            require(batch.readings[0].mapping.confidence == initial.confidence, "runtime reads must not mutate semantic confidence")
        }
        require(initial.confidence == .high, "catalog confidence must remain the catalog value")
        require(api.copyServicesCount == 1, "confidence test must continue using the discovery cache")
    }

    private static func properties(product: String, locationID: Int) -> [String: Any] {
        [
            "Product": product,
            "Manufacturer": "Apple",
            "PrimaryUsagePage": NSNumber(value: HIDTemperatureSourceConstants.primaryUsagePage),
            "PrimaryUsage": NSNumber(value: HIDTemperatureSourceConstants.primaryUsage),
            "VendorID": NSNumber(value: 0),
            "ProductID": NSNumber(value: 0),
            "LocationID": NSNumber(value: locationID)
        ]
    }

    private static func runRealHardwareSmoke() {
        let source = HIDTemperatureSource()
        let discoveryStart = DispatchTime.now().uptimeNanoseconds
        let discovery = source.discover()
        let discoveryMilliseconds = elapsedMilliseconds(since: discoveryStart)

        guard discovery.isSuccessful else {
            print("REAL HID SMOKE: unavailable")
            print("failure: \(discovery.failure?.rawValue ?? "unknown")")
            print("detail: \(discovery.failureDescription ?? "none")")
            exit(2)
        }

        let firstStart = DispatchTime.now().uptimeNanoseconds
        let first = source.sample(timestamp: Date(), hardwareEpoch: 1)
        let firstMilliseconds = elapsedMilliseconds(since: firstStart)

        var cachedTotalMilliseconds = 0.0
        var cachedCycles = 0
        for cycle in 0..<100 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = source.sample(timestamp: Date(), hardwareEpoch: UInt64(cycle + 2))
            cachedTotalMilliseconds += elapsedMilliseconds(since: start)
            cachedCycles += 1
        }

        let validValues = first.readings.compactMap { $0.sample.validCelsius }
        let mappedStorage = discovery.sensors.filter {
            $0.mapping.status == .mapped && $0.mapping.category == .storage
        }
        let mappedPMU = discovery.sensors.filter {
            $0.mapping.status == .mapped && $0.mapping.category == .pmu
        }
        let mappedAmbient = discovery.sensors.filter {
            $0.mapping.status == .mapped && $0.mapping.category == .ambient
        }
        let mappedBattery = discovery.sensors.filter {
            $0.mapping.status == .mapped && $0.mapping.category == .battery
        }
        let mappedCPUGPU = discovery.sensors.filter {
            $0.mapping.status == .mapped && ($0.mapping.category == .cpu || $0.mapping.category == .gpu)
        }

        print("REAL HID SMOKE: available")
        print("service count: \(discovery.sensors.count)")
        print("valid readings: \(validValues.count)/\(first.readings.count)")
        print("observed range: \(formattedRange(validValues))")
        print("storage identities: \(formattedProducts(mappedStorage))")
        print("PMU identities: \(formattedProducts(mappedPMU))")
        print("ambient identities: \(formattedProducts(mappedAmbient))")
        print("battery identities: \(formattedProducts(mappedBattery))")
        print("CPU/GPU mapped promotions: \(mappedCPUGPU.count)")
        print("discovery wall: \(String(format: "%.3f ms", discoveryMilliseconds))")
        print("first sample wall: \(String(format: "%.3f ms", firstMilliseconds))")
        print("cached cycles: \(cachedCycles), average wall: \(String(format: "%.3f ms", cachedTotalMilliseconds / Double(max(cachedCycles, 1))))")
        print("bounded cached repetition: 100 cycles completed")

        require(!discovery.sensors.isEmpty, "real HID smoke must discover at least one service")
        require(!validValues.isEmpty, "real HID smoke must read at least one valid event")
        require(!mappedStorage.isEmpty, "real HID smoke must correlate the M4 storage sensor")
        require(!mappedPMU.isEmpty, "real HID smoke must preserve mapped PMU sensors")
        require(mappedCPUGPU.isEmpty, "real HID smoke must not promote HID readings to CPU/GPU")
        require(source.hasDiscoveryCache && source.cachedSensorCount == discovery.sensors.count, "real smoke must use the discovery cache")
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func formattedRange(_ values: [Double]) -> String {
        guard let minimum = values.min(), let maximum = values.max() else { return "none" }
        return String(format: "%.3f...%.3f °C", minimum, maximum)
    }

    private static func formattedProducts(_ sensors: [HIDDiscoveredTemperatureSensor]) -> String {
        let names = sensors.compactMap { $0.identity.rawName }.sorted()
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
