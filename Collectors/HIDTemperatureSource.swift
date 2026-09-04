import Darwin
import Foundation
import IOKit

enum HIDTemperatureSourceConstants {
    static let iokitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"

    // These values were validated on the target Mac16,12 and in the checked-in
    // hardware differential evidence. They are the IOHIDFamily values for the
    // vendor temperature usage, not chip-specific semantic mappings.
    static let primaryUsagePage: Int32 = 0xFF00
    static let primaryUsage: Int32 = 0x0005

    // IOHIDEventTypes.h defines kIOHIDEventTypeTemperature as 15 and
    // IOHIDEventFieldBase(type) as (type << 16). The field is intentionally
    // kept at the validated base; no experimental offsets are used.
    static let temperatureEventType: Int64 = 15
    static let temperatureEventFieldBase: Int32 = Int32(truncatingIfNeeded: temperatureEventType << 16)

    static let propertyKeys = [
        "Product",
        "Manufacturer",
        "PrimaryUsagePage",
        "PrimaryUsage",
        "VendorID",
        "ProductID",
        "LocationID",
        "RegistryID",
        "IORegistryEntryID",
        "ServiceID",
        "ModelIdentifier",
        "model",
        "ServiceClass",
        "IOClass"
    ]

    static let requiredSymbolNames = [
        "IOHIDEventSystemClientCreate",
        "IOHIDEventSystemClientSetMatching",
        "IOHIDEventSystemClientCopyServices",
        "IOHIDServiceClientCopyProperty",
        "IOHIDServiceClientCopyEvent",
        "IOHIDEventGetFloatValue"
    ]
}

struct HIDTemperatureSymbolAvailability: Sendable, Equatable {
    let libraryPath: String
    let libraryLoaded: Bool
    let symbols: [String: Bool]
    let missingSymbols: [String]

    var requiredSymbolsFound: Bool {
        missingSymbols.isEmpty && libraryLoaded
    }
}

/// Read-only metadata correlated from the native IORegistry. The registry
/// entry ID is useful within the current registry epoch; it is not advertised
/// as a reboot-persistent hardware identifier.
struct HIDRegistryMetadata: Sendable, Equatable {
    let serviceClass: String?
    let registryEntryID: UInt64?
    let registryName: String?
    let modelIdentifier: String?
}

struct HIDDiscoveredTemperatureSensor: Sendable, Equatable {
    let identity: SensorIdentity
    let mapping: SensorMapping
    let rawProperties: [String: String]
}

struct HIDTemperatureDiscovery: Sendable, Equatable {
    let sensors: [HIDDiscoveredTemperatureSensor]
    let availability: TemperatureBackendAvailability
    let failure: TemperatureDiscoveryFailure?
    let failureDescription: String?

    var isSuccessful: Bool {
        failure == nil && availability.isSelectable && !sensors.isEmpty
    }
}

struct HIDTemperatureSampleBatch: Sendable, Equatable {
    let timestamp: Date
    let hardwareEpoch: UInt64
    let readings: [TemperatureSensorReading]
    let coverage: TemperatureCollectionCoverage
    let backendStatus: TemperatureBackendStatus
    let discovery: HIDTemperatureDiscovery
    let failure: TemperatureDiscoveryFailure?

    var validReadings: [TemperatureSensorReading] {
        readings.filter { $0.sample.validCelsius != nil }
    }
}

/// Minimal seam around private IOHID calls. The production implementation is
/// backed by runtime symbol resolution; tests provide this protocol without
/// requiring Apple thermal hardware or private headers.
protocol HIDTemperatureAPI: AnyObject {
    func resolveSymbols() -> HIDTemperatureSymbolAvailability
    func createClient() -> AnyObject?

    /// The Int32 C call shape is the one used by the validated reference
    /// implementation. The return register is not a reliable status on the
    /// target ABI, so the source deliberately ignores it; CopyServices is the
    /// observable discovery result.
    @discardableResult
    func setMatching(
        _ client: AnyObject,
        primaryUsagePage: Int32,
        primaryUsage: Int32
    ) -> Int32

    /// Returned service objects are retained by the returned Swift array and
    /// then by the source cache. The source drops them before dropping client.
    func copyServices(_ client: AnyObject) -> [AnyObject]?
    func copyProperty(_ service: AnyObject, key: String) -> Any?
    func copyEvent(
        _ service: AnyObject,
        eventType: Int64,
        options: Int32,
        matching: Int64
    ) -> AnyObject?
    func getFloatValue(_ event: AnyObject, field: Int32) -> Double

    /// Optional native registry correlation. Failure to correlate is not a
    /// discovery failure because IOHID properties remain authoritative for
    /// raw inventory and sampling.
    func registryMetadata(product: String?, locationID: String?) -> HIDRegistryMetadata?

    func resetMetadataCache()
}

final class IOHIDTemperatureAPI: HIDTemperatureAPI {
    private typealias EventSystemClientCreateFunction = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias EventSystemClientSetMatchingFunction = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias EventSystemClientCopyServicesFunction = @convention(c) (CFTypeRef) -> Unmanaged<AnyObject>?
    private typealias ServiceClientCopyPropertyFunction = @convention(c) (CFTypeRef, CFString) -> Unmanaged<AnyObject>?
    private typealias ServiceClientCopyEventFunction = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias EventGetFloatValueFunction = @convention(c) (CFTypeRef, Int32) -> Double

    private struct ResolvedSymbols {
        let createClient: EventSystemClientCreateFunction
        let setMatching: EventSystemClientSetMatchingFunction
        let copyServices: EventSystemClientCopyServicesFunction
        let copyProperty: ServiceClientCopyPropertyFunction
        let copyEvent: ServiceClientCopyEventFunction
        let getFloatValue: EventGetFloatValueFunction
    }

    private var libraryHandle: UnsafeMutableRawPointer?
    private var resolvedSymbols: ResolvedSymbols?
    private var cachedAvailability: HIDTemperatureSymbolAvailability?
    private var registryMetadataIndex: [String: HIDRegistryMetadata]?

    deinit {
        if let libraryHandle {
            dlclose(libraryHandle)
        }
    }

    func resolveSymbols() -> HIDTemperatureSymbolAvailability {
        if let cachedAvailability {
            return cachedAvailability
        }

        guard let handle = dlopen(HIDTemperatureSourceConstants.iokitPath, RTLD_LAZY | RTLD_LOCAL) else {
            let availability = HIDTemperatureSymbolAvailability(
                libraryPath: HIDTemperatureSourceConstants.iokitPath,
                libraryLoaded: false,
                symbols: Dictionary(uniqueKeysWithValues: HIDTemperatureSourceConstants.requiredSymbolNames.map { ($0, false) }),
                missingSymbols: HIDTemperatureSourceConstants.requiredSymbolNames.sorted()
            )
            cachedAvailability = availability
            return availability
        }

        libraryHandle = handle
        let createClient = Self.resolve(handle: handle, name: "IOHIDEventSystemClientCreate", as: EventSystemClientCreateFunction.self)
        let setMatching = Self.resolve(handle: handle, name: "IOHIDEventSystemClientSetMatching", as: EventSystemClientSetMatchingFunction.self)
        let copyServices = Self.resolve(handle: handle, name: "IOHIDEventSystemClientCopyServices", as: EventSystemClientCopyServicesFunction.self)
        let copyProperty = Self.resolve(handle: handle, name: "IOHIDServiceClientCopyProperty", as: ServiceClientCopyPropertyFunction.self)
        let copyEvent = Self.resolve(handle: handle, name: "IOHIDServiceClientCopyEvent", as: ServiceClientCopyEventFunction.self)
        let getFloatValue = Self.resolve(handle: handle, name: "IOHIDEventGetFloatValue", as: EventGetFloatValueFunction.self)

        let symbols: [String: Bool] = [
            "IOHIDEventSystemClientCreate": createClient != nil,
            "IOHIDEventSystemClientSetMatching": setMatching != nil,
            "IOHIDEventSystemClientCopyServices": copyServices != nil,
            "IOHIDServiceClientCopyProperty": copyProperty != nil,
            "IOHIDServiceClientCopyEvent": copyEvent != nil,
            "IOHIDEventGetFloatValue": getFloatValue != nil
        ]
        let missingSymbols = symbols.filter { !$0.value }.map(\.key).sorted()
        let availability = HIDTemperatureSymbolAvailability(
            libraryPath: HIDTemperatureSourceConstants.iokitPath,
            libraryLoaded: true,
            symbols: symbols,
            missingSymbols: missingSymbols
        )
        cachedAvailability = availability

        if let createClient, let setMatching, let copyServices, let copyProperty, let copyEvent, let getFloatValue,
           missingSymbols.isEmpty {
            resolvedSymbols = ResolvedSymbols(
                createClient: createClient,
                setMatching: setMatching,
                copyServices: copyServices,
                copyProperty: copyProperty,
                copyEvent: copyEvent,
                getFloatValue: getFloatValue
            )
        }
        return availability
    }

    func createClient() -> AnyObject? {
        guard let symbols = resolvedSymbols,
              let unmanagedClient = symbols.createClient(kCFAllocatorDefault) else {
            return nil
        }
        // Create returns a retained CF object. ARC owns the transferred object.
        return unmanagedClient.takeRetainedValue()
    }

    @discardableResult
    func setMatching(
        _ client: AnyObject,
        primaryUsagePage: Int32,
        primaryUsage: Int32
    ) -> Int32 {
        guard let symbols = resolvedSymbols else { return -1 }
        guard let matching = Self.makeMatchingDictionary(
            primaryUsagePage: primaryUsagePage,
            primaryUsage: primaryUsage
        ) else {
            return -1
        }
        return symbols.setMatching(client as CFTypeRef, matching)
    }

    func copyServices(_ client: AnyObject) -> [AnyObject]? {
        guard let symbols = resolvedSymbols,
              let unmanagedServices = symbols.copyServices(client as CFTypeRef) else {
            return nil
        }

        // CopyServices returns a retained array. Each object is copied into a
        // strong Swift array before the CF array's ownership is released.
        let retainedArray = unmanagedServices.takeRetainedValue()
        guard let array = retainedArray as? NSArray else { return [] }
        return array.compactMap { $0 as AnyObject }
    }

    func copyProperty(_ service: AnyObject, key: String) -> Any? {
        guard let symbols = resolvedSymbols,
              let unmanagedValue = symbols.copyProperty(service as CFTypeRef, key as CFString) else {
            return nil
        }
        // CopyProperty returns a retained CF value; the returned Any is ARC-owned.
        return unmanagedValue.takeRetainedValue()
    }

    func copyEvent(
        _ service: AnyObject,
        eventType: Int64,
        options: Int32,
        matching: Int64
    ) -> AnyObject? {
        guard let symbols = resolvedSymbols,
              let unmanagedEvent = symbols.copyEvent(service as CFTypeRef, eventType, options, matching) else {
            return nil
        }
        // CopyEvent returns a retained event. The caller's local AnyObject owns it.
        return unmanagedEvent.takeRetainedValue()
    }

    func getFloatValue(_ event: AnyObject, field: Int32) -> Double {
        guard let symbols = resolvedSymbols else { return .nan }
        return symbols.getFloatValue(event as CFTypeRef, field)
    }

    func registryMetadata(product: String?, locationID: String?) -> HIDRegistryMetadata? {
        if registryMetadataIndex == nil {
            registryMetadataIndex = buildRegistryMetadataIndex()
        }
        guard let key = Self.correlationKey(product: product, locationID: locationID) else {
            return nil
        }
        return registryMetadataIndex?[key]
    }

    func resetMetadataCache() {
        registryMetadataIndex = nil
    }

    private func buildRegistryMetadataIndex() -> [String: HIDRegistryMetadata] {
        // This is read-only registry correlation only. It does not enumerate
        // arbitrary all-services HID data and it does not affect sampling.
        guard let matching = IOServiceMatching("IOHIDEventService") else {
            return [:]
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var result: [String: HIDRegistryMetadata] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let properties = registryProperties(for: service),
                  let product = Self.stringValue(properties["Product"]),
                  let locationID = Self.scalarValue(properties["LocationID"]),
                  let key = Self.correlationKey(product: product, locationID: locationID) else {
                continue
            }

            let metadata = HIDRegistryMetadata(
                serviceClass: ioObjectClass(service),
                registryEntryID: registryEntryID(for: service),
                registryName: ioRegistryName(service),
                modelIdentifier: Self.stringValue(properties["model"])
                    ?? Self.stringValue(properties["ModelIdentifier"])
            )

            if let existing = result[key],
               let existingID = existing.registryEntryID,
               let newID = metadata.registryEntryID,
               existingID <= newID {
                continue
            }
            result[key] = metadata
        }
        return result
    }

    private func registryProperties(for service: io_service_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS, let unmanagedProperties else {
            return nil
        }

        let dictionary = unmanagedProperties.takeRetainedValue() as NSDictionary
        var properties: [String: Any] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String else { continue }
            properties[key] = value
        }
        return properties
    }

    private func registryEntryID(for service: io_service_t) -> UInt64? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
              entryID != 0 else {
            return nil
        }
        return entryID
    }

    private func ioRegistryName(_ service: io_service_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            IORegistryEntryGetName(service, pointer.baseAddress)
        }
        guard result == KERN_SUCCESS else { return nil }
        return String(cString: buffer)
    }

    private func ioObjectClass(_ service: io_service_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            IOObjectGetClass(service, pointer.baseAddress)
        }
        guard result == KERN_SUCCESS else { return nil }
        return String(cString: buffer)
    }

    private static func correlationKey(product: String?, locationID: String?) -> String? {
        guard let product = product?.trimmingCharacters(in: .whitespacesAndNewlines),
              !product.isEmpty,
              let locationID = locationID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locationID.isEmpty else {
            return nil
        }
        return "\(product)\u{001F}\(locationID)"
    }

    private static func makeMatchingDictionary(
        primaryUsagePage: Int32,
        primaryUsage: Int32
    ) -> CFDictionary? {
        // Keep the exact CFNumber/CFDictionary construction used by the
        // validated reference path. Bridging a Swift dictionary is not relied
        // upon for this private API boundary.
        var page = primaryUsagePage
        var usage = primaryUsage
        guard let pageNumber = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &page),
              let usageNumber = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &usage) else {
            return nil
        }

        let keys: [CFString] = ["PrimaryUsagePage" as CFString, "PrimaryUsage" as CFString]
        let values: [CFNumber] = [pageNumber, usageNumber]
        var keyPointers: [UnsafeRawPointer?] = keys.map {
            UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque())
        }
        var valuePointers: [UnsafeRawPointer?] = values.map {
            UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque())
        }
        var keyCallbacks = kCFTypeDictionaryKeyCallBacks
        var valueCallbacks = kCFTypeDictionaryValueCallBacks
        return keyPointers.withUnsafeMutableBufferPointer { keyBuffer in
            valuePointers.withUnsafeMutableBufferPointer { valueBuffer in
                CFDictionaryCreate(
                    kCFAllocatorDefault,
                    keyBuffer.baseAddress,
                    valueBuffer.baseAddress,
                    keys.count,
                    &keyCallbacks,
                    &valueCallbacks
                )
            }
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let string = value as? NSString {
            let trimmed = String(string).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func scalarValue(_ value: Any?) -> String? {
        if let number = value as? NSNumber {
            return String(number.uint64Value)
        }
        return stringValue(value)
    }

    private static func resolve<T>(handle: UnsafeMutableRawPointer, name: String, as type: T.Type) -> T? {
        name.withCString { symbolName in
            guard let raw = dlsym(handle, symbolName) else { return nil }
            return unsafeBitCast(raw, to: type)
        }
    }
}

final class HIDTemperatureSource {
    private struct CachedSensor {
        let service: AnyObject
        let identity: SensorIdentity
        let mapping: SensorMapping
        let rawProperties: [String: String]
    }

    private let api: any HIDTemperatureAPI
    private let catalog: SensorCatalog
    private let socFamily: String?
    private let macOSBuild: String?
    private var client: AnyObject?
    private var cachedSensors: [CachedSensor] = []
    private var discoveryCache: HIDTemperatureDiscovery?

    init(
        api: any HIDTemperatureAPI = IOHIDTemperatureAPI(),
        catalog: SensorCatalog = .initial,
        socFamily: String? = nil,
        macOSBuild: String? = nil
    ) {
        self.api = api
        self.catalog = catalog
        self.socFamily = socFamily
        self.macOSBuild = macOSBuild
    }

    deinit {
        invalidate()
    }

    var hasDiscoveryCache: Bool {
        discoveryCache != nil
    }

    var cachedSensorCount: Int {
        cachedSensors.count
    }

    func discover() -> HIDTemperatureDiscovery {
        if let discoveryCache {
            return discoveryCache
        }

        let symbolAvailability = api.resolveSymbols()
        guard symbolAvailability.libraryLoaded else {
            return cacheFailure(
                .symbolUnavailable,
                description: "IOKit framework could not be loaded"
            )
        }
        guard symbolAvailability.requiredSymbolsFound else {
            return cacheFailure(
                .symbolUnavailable,
                description: "required private IOHID symbol missing: \(symbolAvailability.missingSymbols.joined(separator: ", "))"
            )
        }
        guard let createdClient = api.createClient() else {
            return cacheFailure(
                .clientCreationFailed,
                description: "IOHIDEventSystemClientCreate returned nil"
            )
        }
        client = createdClient

        _ = api.setMatching(
            createdClient,
            primaryUsagePage: HIDTemperatureSourceConstants.primaryUsagePage,
            primaryUsage: HIDTemperatureSourceConstants.primaryUsage
        )

        guard let services = api.copyServices(createdClient) else {
            releaseDiscoveryResources()
            let failure = copyServicesFailure()
            return cacheFailure(
                failure.failure,
                description: failure.description
            )
        }
        guard !services.isEmpty else {
            releaseDiscoveryResources()
            return cacheFailure(
                .noUsableSensors,
                description: "temperature usage matching returned zero services"
            )
        }

        var usedIdentifiers = Set<String>()
        cachedSensors = services.enumerated().map { index, service in
            let rawProperties = readRawProperties(from: service)
            let product = stringValue(rawProperties: rawProperties, key: "Product")
            let locationID = scalarValue(rawProperties: rawProperties, key: "LocationID")
            let registryMetadata = api.registryMetadata(product: product, locationID: locationID)
            let serviceClass = registryMetadata?.serviceClass
                ?? stringValue(rawProperties: rawProperties, key: "ServiceClass")
                ?? stringValue(rawProperties: rawProperties, key: "IOClass")
            let modelIdentifier = registryMetadata?.modelIdentifier
                ?? stringValue(rawProperties: rawProperties, key: "ModelIdentifier")
                ?? stringValue(rawProperties: rawProperties, key: "model")
            let rawIdentifier = makeRawIdentifier(
                rawProperties: rawProperties,
                product: product,
                locationID: locationID,
                serviceClass: serviceClass,
                registryMetadata: registryMetadata,
                index: index,
                usedIdentifiers: &usedIdentifiers
            )
            let identity = SensorIdentity(
                source: .ioHID,
                rawIdentifier: rawIdentifier,
                rawName: product,
                serviceClass: serviceClass,
                modelIdentifier: modelIdentifier
            )
            let mapping = catalog.mapping(
                for: identity,
                socFamily: socFamily,
                macOSBuild: macOSBuild
            ) ?? SensorMapping(status: .unmapped)
            return CachedSensor(
                service: service,
                identity: identity,
                mapping: mapping,
                rawProperties: rawProperties
            )
        }

        let sensors = cachedSensors.map {
            HIDDiscoveredTemperatureSensor(
                identity: $0.identity,
                mapping: $0.mapping,
                rawProperties: $0.rawProperties
            )
        }
        let discovery = HIDTemperatureDiscovery(
            sensors: sensors,
            availability: .available,
            failure: nil,
            failureDescription: nil
        )
        discoveryCache = discovery
        return discovery
    }

    func sample(
        timestamp: Date = Date(),
        hardwareEpoch: UInt64
    ) -> HIDTemperatureSampleBatch {
        let discovery = discover()
        guard discovery.isSuccessful, !cachedSensors.isEmpty else {
            let coverage = TemperatureCollectionCoverage(
                attemptedCount: 0,
                validCount: 0,
                failedCount: 0,
                invalidCount: 0,
                transportFailure: true
            )
            let backendStatus = backendStatus(for: discovery, coverage: coverage)
            return HIDTemperatureSampleBatch(
                timestamp: timestamp,
                hardwareEpoch: hardwareEpoch,
                readings: [],
                coverage: coverage,
                backendStatus: backendStatus,
                discovery: discovery,
                failure: discovery.failure
            )
        }

        var readings: [TemperatureSensorReading] = []
        readings.reserveCapacity(cachedSensors.count)
        for sensor in cachedSensors {
            let sample: TemperatureSample
            if let event = api.copyEvent(
                sensor.service,
                eventType: HIDTemperatureSourceConstants.temperatureEventType,
                options: 0,
                matching: 0
            ) {
                let rawCelsius = api.getFloatValue(
                    event,
                    field: HIDTemperatureSourceConstants.temperatureEventFieldBase
                )
                // TemperatureValidator owns finite, sentinel, and physical
                // range policy. No source-layer clamping or fallback occurs.
                sample = TemperatureValidator.validate(rawCelsius)
            } else {
                sample = .readFailed(code: "IOHIDServiceClientCopyEvent returned nil")
            }

            readings.append(
                TemperatureSensorReading(
                    identity: sensor.identity,
                    mapping: sensor.mapping,
                    sample: sample,
                    timestamp: timestamp,
                    hardwareEpoch: hardwareEpoch
                )
            )
        }

        let coverage = collectionCoverage(for: readings)
        let backendStatus = backendStatus(for: discovery, coverage: coverage)
        return HIDTemperatureSampleBatch(
            timestamp: timestamp,
            hardwareEpoch: hardwareEpoch,
            readings: readings,
            coverage: coverage,
            backendStatus: backendStatus,
            discovery: discovery,
            failure: nil
        )
    }

    /// Drops only this source's hardware/cache ownership. Hardware epoch and
    /// lifecycle decisions belong to the future ThermalCollector owner.
    func invalidate() {
        releaseDiscoveryResources()
        discoveryCache = nil
        api.resetMetadataCache()
    }

    private func cacheFailure(
        _ failure: TemperatureDiscoveryFailure,
        description: String
    ) -> HIDTemperatureDiscovery {
        let availability = TemperatureBackendHealthClassifier().discoveryFailureStatus(
            source: .ioHID,
            failure: failure
        ).availability
        let discovery = HIDTemperatureDiscovery(
            sensors: [],
            availability: availability,
            failure: failure,
            failureDescription: description
        )
        discoveryCache = discovery
        return discovery
    }

    private func backendStatus(
        for discovery: HIDTemperatureDiscovery,
        coverage: TemperatureCollectionCoverage
    ) -> TemperatureBackendStatus {
        guard discovery.failure == nil else {
            return TemperatureBackendHealthClassifier().discoveryFailureStatus(
                source: .ioHID,
                failure: discovery.failure ?? .backendUnsupported
            )
        }
        let assessment = TemperatureBackendHealthClassifier().classify(coverage: coverage)
        return TemperatureBackendStatus(
            source: .ioHID,
            availability: assessment.availability,
            runtimeHealth: assessment.runtimeHealth
        )
    }

    private func collectionCoverage(for readings: [TemperatureSensorReading]) -> TemperatureCollectionCoverage {
        var validCount = 0
        var failedCount = 0
        var invalidCount = 0
        for reading in readings {
            switch reading.sample.status {
            case .valid:
                validCount += 1
            case .readFailed:
                failedCount += 1
            case .invalidSample:
                invalidCount += 1
            case .stale, .notSampled:
                break
            }
        }
        return TemperatureCollectionCoverage(
            attemptedCount: readings.count,
            validCount: validCount,
            failedCount: failedCount,
            invalidCount: invalidCount
        )
    }

    private func readRawProperties(from service: AnyObject) -> [String: String] {
        var result: [String: String] = [:]
        for key in HIDTemperatureSourceConstants.propertyKeys {
            guard let value = api.copyProperty(service, key: key),
                  let display = displayString(value) else {
                continue
            }
            result[key] = display
        }
        return result
    }

    private func displayString(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let string = value as? NSString {
            let trimmed = String(string).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func stringValue(rawProperties: [String: String], key: String) -> String? {
        guard let value = rawProperties[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func scalarValue(rawProperties: [String: String], key: String) -> String? {
        stringValue(rawProperties: rawProperties, key: key)
    }

    private func makeRawIdentifier(
        rawProperties: [String: String],
        product: String?,
        locationID: String?,
        serviceClass: String?,
        registryMetadata: HIDRegistryMetadata?,
        index: Int,
        usedIdentifiers: inout Set<String>
    ) -> String {
        let registryIdentifier = registryMetadata?.registryEntryID.map(String.init)
            ?? firstPropertyValue(
                rawProperties: rawProperties,
                keys: ["RegistryID", "IORegistryEntryID", "ServiceID"]
            )
        let base: String
        if let registryIdentifier {
            base = "IORegistryEntryID=\(registryIdentifier)"
        } else if let serviceClass, let product, let locationID {
            base = "service=\(serviceClass)|product=\(product)|location=\(locationID)"
        } else if let locationID {
            // LocationID is the best raw service identity exposed directly by
            // this IOHID API on the target. It is not asserted reboot-stable.
            base = "LocationID=\(locationID)"
        } else if let serviceClass, let product {
            base = "service=\(serviceClass)|product=\(product)"
        } else {
            base = "epoch-local-index=\(index)"
        }

        var candidate = base
        var ordinal = 2
        while !usedIdentifiers.insert(candidate).inserted {
            candidate = "\(base)#\(ordinal)"
            ordinal += 1
        }
        return candidate
    }

    private func firstPropertyValue(rawProperties: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(rawProperties: rawProperties, key: key) {
                return value
            }
        }
        return nil
    }

    private func copyServicesFailure() -> (failure: TemperatureDiscoveryFailure, description: String) {
        // An explicit App Sandbox marker is sufficient evidence to name this
        // case. Without it, a nil result remains the generic IOKit failure;
        // this avoids speculative environment diagnosis.
        if let marker = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"],
           !marker.isEmpty {
            return (
                .sandboxRestricted,
                "IOHIDEventSystemClientCopyServices returned nil in an App Sandbox process"
            )
        }
        return (
            .copyServicesUnavailable,
            "IOHIDEventSystemClientCopyServices returned nil"
        )
    }

    private func releaseDiscoveryResources() {
        // Service references must be dropped before their owning client. Both
        // are ARC-owned AnyObject values transferred by the API seam.
        cachedSensors.removeAll()
        client = nil
    }
}
