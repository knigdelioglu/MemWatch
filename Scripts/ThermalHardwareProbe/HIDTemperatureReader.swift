import Darwin
import Foundation

// This file is intentionally an isolated diagnostic backend. It is not part
// of the MemWatch Xcode target and it never mutates HID or SMC state.

enum HIDProbeConstants {
    static let iokitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"

    // These values are copied as declarations from the public-source
    // IOHIDFamily references below; they are not guessed chip-specific names.
    // PrimaryUsagePage/PrimaryUsage:
    // https://chromium.googlesource.com/chromium/src/+/c21e9f71d1f2e/components/power_metrics/m1_sensors_internal_types_mac.h
    static let primaryUsagePage: Int32 = 0xFF00
    static let primaryUsage: Int32 = 0x0005

    // IOHIDEventTypes.h declares kIOHIDEventTypeTemperature as 15 and
    // IOHIDEventFieldBase(type) as (type << 16):
    // https://github.com/freedomtan/sensors_cmdline/blob/main/sensors.m
    // https://github.com/blueboxd/IOHIDFamily-368.21/blob/main/IOHIDFamily/IOHIDEventData.h
    static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    static let temperatureEventFieldBase: Int32 = Int32(truncatingIfNeeded: temperatureEventType << 16)

    // A broad diagnostic range rejects obvious decoder failures without
    // converting or clamping a real observation.
    static let minimumTemperatureCelsius = -40.0
    static let maximumTemperatureCelsius = 125.0

    static let propertyKeys = [
        "Product",
        "Manufacturer",
        "PrimaryUsagePage",
        "PrimaryUsage",
        "Transport",
        "VendorID",
        "ProductID",
        "LocationID",
        "RegistryID",
        "IORegistryEntryID",
        "ServiceID",
        "VendorIDSource",
        "Version",
        "CountryCode",
        "DeviceUsagePairs",
        "HIDEventServiceProperties",
        "HIDEventSystemClientType"
    ]
}

struct HIDSymbolAvailability: Codable {
    let libraryPath: String
    let libraryLoaded: Bool
    let symbols: [String: Bool]
    let requiredSymbolsFound: Bool
    let missingSymbols: [String]
}

struct HIDMatchingReport: Codable {
    let primaryUsagePage: Int32
    let primaryUsage: Int32
    let matchingConfigured: Bool
    let matchingResult: String?
    let discoveryStatus: String
    let discoveryError: String?
}

struct HIDPropertyValue: Codable {
    let kind: String
    let stringValue: String?
    let signedInteger: Int64?
    let unsignedInteger: String?
    let doubleValue: Double?
    let boolValue: Bool?
    let rawHex: String?
    let objectValue: [String: HIDPropertyValue]?
    let arrayValue: [HIDPropertyValue]?

    var displayString: String? {
        if let stringValue { return stringValue }
        if let signedInteger { return String(signedInteger) }
        if let unsignedInteger { return unsignedInteger }
        if let doubleValue { return String(doubleValue) }
        if let boolValue { return String(boolValue) }
        if let rawHex { return "0x\(rawHex)" }
        return nil
    }

    static func make(_ value: Any, depth: Int = 0) -> HIDPropertyValue {
        if let string = value as? String {
            return HIDPropertyValue(
                kind: "string",
                stringValue: string,
                signedInteger: nil,
                unsignedInteger: nil,
                doubleValue: nil,
                boolValue: nil,
                rawHex: nil,
                objectValue: nil,
                arrayValue: nil
            )
        }

        if let string = value as? NSString {
            return HIDPropertyValue(
                kind: "string",
                stringValue: string as String,
                signedInteger: nil,
                unsignedInteger: nil,
                doubleValue: nil,
                boolValue: nil,
                rawHex: nil,
                objectValue: nil,
                arrayValue: nil
            )
        }

        if let number = value as? NSNumber {
            let objCType = String(cString: number.objCType)
            let double = number.doubleValue
            return HIDPropertyValue(
                kind: "NSNumber",
                stringValue: nil,
                signedInteger: number.int64Value,
                unsignedInteger: String(number.uint64Value),
                doubleValue: double.isFinite ? double : nil,
                boolValue: objCType == "B" ? number.boolValue : nil,
                rawHex: nil,
                objectValue: nil,
                arrayValue: nil
            )
        }

        if let data = value as? Data {
            return HIDPropertyValue(
                kind: "CFData",
                stringValue: nil,
                signedInteger: nil,
                unsignedInteger: nil,
                doubleValue: nil,
                boolValue: nil,
                rawHex: data.map { String(format: "%02x", $0) }.joined(),
                objectValue: nil,
                arrayValue: nil
            )
        }

        if depth >= 6 {
            return HIDPropertyValue(
                kind: "opaque-depth-limit",
                stringValue: String(describing: value),
                signedInteger: nil,
                unsignedInteger: nil,
                doubleValue: nil,
                boolValue: nil,
                rawHex: nil,
                objectValue: nil,
                arrayValue: nil
            )
        }

        if let entries = hidDictionaryEntries(value) {
            let object = Dictionary(uniqueKeysWithValues: entries.sorted { $0.0 < $1.0 }.map { key, child in
                (key, HIDPropertyValue.make(child, depth: depth + 1))
            })
            return HIDPropertyValue(
                kind: "dictionary",
                stringValue: nil,
                signedInteger: nil,
                unsignedInteger: nil,
                doubleValue: nil,
                boolValue: nil,
                rawHex: nil,
                objectValue: object,
                arrayValue: nil
            )
        }

        if let array = value as? NSArray {
            return HIDPropertyValue(
                kind: "array",
                stringValue: nil,
                signedInteger: nil,
                unsignedInteger: nil,
                doubleValue: nil,
                boolValue: nil,
                rawHex: nil,
                objectValue: nil,
                arrayValue: array.map { HIDPropertyValue.make($0, depth: depth + 1) }
            )
        }

        return HIDPropertyValue(
            kind: "opaque",
            stringValue: String(describing: value),
            signedInteger: nil,
            unsignedInteger: nil,
            doubleValue: nil,
            boolValue: nil,
            rawHex: nil,
            objectValue: nil,
            arrayValue: nil
        )
    }
}

private func hidDictionaryEntries(_ value: Any) -> [(String, Any)]? {
    if let dictionary = value as? [String: Any] {
        return dictionary.map { ($0.key, $0.value) }
    }
    if let dictionary = value as? NSDictionary {
        return dictionary.compactMap { key, value in
            guard let key = key as? String else { return nil }
            return (key, value)
        }
    }
    return nil
}

struct HIDSensorClassification: Codable {
    var category: String
    var confidence: String
    var evidence: String
}

struct HIDTemperatureSample: Codable {
    let timestamp: Date
    let serviceIdentifier: String
    let product: String?
    let rawEventPresent: Bool
    let decodedCelsius: Double?
    let finite: Bool
    let status: String
    let result: String
    let timestampSource: String
    let error: String?
}

struct HIDTemperatureStatistics: Codable {
    let sampleCount: Int
    let validSampleCount: Int
    let invalidSampleCount: Int
    let first: Double?
    let last: Double?
    let minimum: Double?
    let average: Double?
    let maximum: Double?
    let delta: Double?
    let standardDeviation: Double?
}

struct HIDDuplicateCandidate: Codable {
    let otherServiceIdentifier: String
    let reason: String
    let correlation: String?
}

struct HIDTemperatureServiceEvidence: Codable {
    let id: String
    let idSource: String
    let product: String?
    let properties: [String: HIDPropertyValue]
    let propertyErrors: [String]
    var classification: String
    var confidence: String
    var classificationEvidence: String
    let samples: [HIDTemperatureSample]
    let statistics: HIDTemperatureStatistics?
    let duplicateCandidates: [HIDDuplicateCandidate]
}

struct HIDResourceCleanupReport: Codable {
    let serviceArrayReleaseAttempted: Bool
    let serviceArrayReleased: Bool
    let clientReleaseAttempted: Bool
    let clientReleased: Bool
    let libraryCloseAttempted: Bool
    let libraryClosed: Bool
}

struct HIDPerformanceReport: Codable {
    let initialDiscoveryWallDurationMilliseconds: Double
    let initialDiscoveryCPUTimeMilliseconds: Double?
    let firstSampleReadWallDurationMilliseconds: Double
    let firstSampleReadCPUTimeMilliseconds: Double?
    let cachedSampleReadCount: Int
    let cachedSampleReadWallDurationMilliseconds: Double
    let cachedSampleReadCPUTimeMilliseconds: Double?
    let serviceCount: Int
    let eventReadCount: Int
    let successfulEventReadCount: Int
    let failedEventReadCount: Int
    let discoveryStrategy: String
}

struct HIDBackendReport: Codable {
    let available: Bool
    let symbols: [String: Bool]
    let symbolAvailability: HIDSymbolAvailability
    let matching: HIDMatchingReport
    let serviceCount: Int
    let eventReadCount: Int
    let successfulEventReadCount: Int
    let failedEventReadCount: Int
    let errors: [String]
    let performance: HIDPerformanceReport
    let resourceCleanup: HIDResourceCleanupReport
}

private typealias HIDEventSystemClientCreateFunction = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
// Current Swift/Objective-C declarations expose SetMatching as void. Do not
// interpret an undefined return register as an IOReturn status.
private typealias HIDEventSystemClientSetMatchingFunction = @convention(c) (CFTypeRef, CFDictionary) -> Void
private typealias HIDEventSystemClientCopyServicesFunction = @convention(c) (CFTypeRef) -> Unmanaged<AnyObject>?
private typealias HIDServiceClientCopyPropertyFunction = @convention(c) (CFTypeRef, CFString) -> Unmanaged<AnyObject>?
private typealias HIDServiceClientCopyEventFunction = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
private typealias HIDEventGetFloatValueFunction = @convention(c) (CFTypeRef, Int32) -> Double

private final class HIDDiscoveredService {
    let identifier: String
    let idSource: String
    let product: String?
    let properties: [String: HIDPropertyValue]
    let propertyErrors: [String]
    let service: CFTypeRef
    var classification: HIDSensorClassification
    var samples: [HIDTemperatureSample] = []
    var duplicateCandidates: [HIDDuplicateCandidate] = []

    init(
        identifier: String,
        idSource: String,
        product: String?,
        properties: [String: HIDPropertyValue],
        propertyErrors: [String],
        service: CFTypeRef
    ) {
        self.identifier = identifier
        self.idSource = idSource
        self.product = product
        self.properties = properties
        self.propertyErrors = propertyErrors
        self.service = service
        self.classification = classifyHIDProduct(product)
    }
}

final class HIDTemperatureReader {
    private var libraryHandle: UnsafeMutableRawPointer?
    private let createClient: HIDEventSystemClientCreateFunction?
    private let setMatching: HIDEventSystemClientSetMatchingFunction?
    private let copyServices: HIDEventSystemClientCopyServicesFunction?
    private let copyProperty: HIDServiceClientCopyPropertyFunction?
    private let copyEvent: HIDServiceClientCopyEventFunction?
    private let getFloatValue: HIDEventGetFloatValueFunction?

    // takeRetainedValue() transfers the Copy/Create ownership to ARC. Setting
    // these references to nil in close() performs the corresponding release.
    private var client: AnyObject?
    private var serviceArray: AnyObject?
    private var discovered = false
    private var backendAvailable = false
    private var matchingConfigured = false
    private var matchingResult: String?
    private var discoveryStatus = "notAttempted"
    private var discoveryError: String?
    private var errors: [String] = []
    private var services: [HIDDiscoveredService] = []

    private var discoveryWallDurationMilliseconds = 0.0
    private var discoveryCPUTimeMilliseconds: Double?
    private var firstSampleReadWallDurationMilliseconds = 0.0
    private var firstSampleReadCPUTimeMilliseconds: Double?
    private var cachedSampleReadWallDurationMilliseconds = 0.0
    private var cachedSampleReadCPUTimeMilliseconds: Double?
    private var cachedSampleReadCount = 0
    private var eventReadCount = 0
    private var successfulEventReadCount = 0
    private var failedEventReadCount = 0

    private var serviceArrayReleaseAttempted = false
    private var serviceArrayReleased = false
    private var clientReleaseAttempted = false
    private var clientReleased = false
    private var libraryCloseAttempted = false
    private var libraryClosed = false

    let symbolAvailability: HIDSymbolAvailability

    init() {
        let handle = dlopen(HIDProbeConstants.iokitPath, RTLD_LAZY | RTLD_LOCAL)
        libraryHandle = handle

        createClient = Self.resolve(handle: handle, name: "IOHIDEventSystemClientCreate", as: HIDEventSystemClientCreateFunction.self)
        setMatching = Self.resolve(handle: handle, name: "IOHIDEventSystemClientSetMatching", as: HIDEventSystemClientSetMatchingFunction.self)
        copyServices = Self.resolve(handle: handle, name: "IOHIDEventSystemClientCopyServices", as: HIDEventSystemClientCopyServicesFunction.self)
        copyProperty = Self.resolve(handle: handle, name: "IOHIDServiceClientCopyProperty", as: HIDServiceClientCopyPropertyFunction.self)
        copyEvent = Self.resolve(handle: handle, name: "IOHIDServiceClientCopyEvent", as: HIDServiceClientCopyEventFunction.self)
        getFloatValue = Self.resolve(handle: handle, name: "IOHIDEventGetFloatValue", as: HIDEventGetFloatValueFunction.self)

        let symbols: [String: Bool] = [
            "IOHIDEventSystemClientCreate": createClient != nil,
            "IOHIDEventSystemClientSetMatching": setMatching != nil,
            "IOHIDEventSystemClientCopyServices": copyServices != nil,
            "IOHIDServiceClientCopyProperty": copyProperty != nil,
            "IOHIDServiceClientCopyEvent": copyEvent != nil,
            "IOHIDEventGetFloatValue": getFloatValue != nil
        ]
        let missing = symbols.filter { !$0.value }.map(\.key).sorted()
        symbolAvailability = HIDSymbolAvailability(
            libraryPath: HIDProbeConstants.iokitPath,
            libraryLoaded: handle != nil,
            symbols: symbols,
            requiredSymbolsFound: missing.isEmpty,
            missingSymbols: missing
        )
    }

    deinit {
        close()
    }

    @discardableResult
    func discover() -> Bool {
        guard !discovered else { return backendAvailable }
        discovered = true
        let wallStart = hidMonotonicSeconds()
        let cpuStart = hidProcessCPUSeconds()
        defer {
            discoveryWallDurationMilliseconds = (hidMonotonicSeconds() - wallStart) * 1_000
            discoveryCPUTimeMilliseconds = hidProcessCPUSeconds().flatMap { end in
                cpuStart.map { (end - $0) * 1_000 }
            }
        }

        guard symbolAvailability.libraryLoaded else {
            discoveryStatus = "unavailable"
            discoveryError = "IOKit framework could not be loaded"
            errors.append(discoveryError!)
            return false
        }
        guard symbolAvailability.requiredSymbolsFound,
              let createClient,
              let setMatching,
              let copyServices,
              copyProperty != nil,
              copyEvent != nil,
              getFloatValue != nil else {
            discoveryStatus = "unavailable"
            discoveryError = "required private IOHID symbol missing: \(symbolAvailability.missingSymbols.joined(separator: ", "))"
            errors.append(discoveryError!)
            return false
        }
        guard let unmanagedClient = createClient(kCFAllocatorDefault) else {
            discoveryStatus = "clientCreateFailed"
            discoveryError = "IOHIDEventSystemClientCreate returned nil"
            errors.append(discoveryError!)
            return false
        }

        client = unmanagedClient.takeRetainedValue()
        backendAvailable = true

        let matching: CFDictionary = [
            "PrimaryUsagePage": NSNumber(value: HIDProbeConstants.primaryUsagePage),
            "PrimaryUsage": NSNumber(value: HIDProbeConstants.primaryUsage)
        ] as CFDictionary
        setMatching(client! as CFTypeRef, matching)
        matchingResult = "void API; no return code"
        matchingConfigured = true

        guard let unmanagedServices = copyServices(client! as CFTypeRef) else {
            discoveryStatus = "noServices"
            discoveryError = "IOHIDEventSystemClientCopyServices returned nil"
            errors.append(discoveryError!)
            return true
        }

        let retainedServices = unmanagedServices.takeRetainedValue()
        serviceArray = retainedServices
        let array = retainedServices as! NSArray
        var usedIdentifiers = Set<String>()

        for index in 0..<array.count {
            let service = array.object(at: index) as AnyObject as CFTypeRef
            var properties: [String: HIDPropertyValue] = [:]
            let propertyErrors: [String] = []

            for key in HIDProbeConstants.propertyKeys {
                guard let value = copyPropertyValue(service, key: key) else { continue }
                properties[key] = HIDPropertyValue.make(value)
            }

            let product = properties["Product"]?.stringValue
            let identity = serviceIdentity(properties: properties, index: index, usedIdentifiers: &usedIdentifiers)
            services.append(
                HIDDiscoveredService(
                    identifier: identity.identifier,
                    idSource: identity.source,
                    product: product,
                    properties: properties,
                    propertyErrors: propertyErrors,
                    service: service
                )
            )
        }

        discoveryStatus = services.isEmpty ? "noServices" : "completed"
        if services.isEmpty {
            discoveryError = "temperature usage matching returned zero services"
            errors.append(discoveryError!)
        }
        return true
    }

    @discardableResult
    func readSample(at timestamp: Date) -> Int {
        guard discover(), let copyEvent, let getFloatValue else { return 0 }
        let wallStart = hidMonotonicSeconds()
        let cpuStart = hidProcessCPUSeconds()

        for service in services {
            eventReadCount += 1
            guard let unmanagedEvent = copyEvent(
                service.service,
                HIDProbeConstants.temperatureEventType,
                0,
                0
            ) else {
                failedEventReadCount += 1
                service.samples.append(
                    HIDTemperatureSample(
                        timestamp: timestamp,
                        serviceIdentifier: service.identifier,
                        product: service.product,
                        rawEventPresent: false,
                        decodedCelsius: nil,
                        finite: false,
                        status: "readFailed",
                        result: "IOHIDServiceClientCopyEvent returned nil",
                        timestampSource: "host collection time",
                        error: "temperature event unavailable"
                    )
                )
                continue
            }

            successfulEventReadCount += 1
            let event = unmanagedEvent.takeRetainedValue() as CFTypeRef
            let value = getFloatValue(event, HIDProbeConstants.temperatureEventFieldBase)
            let sample: HIDTemperatureSample
            if !value.isFinite {
                sample = HIDTemperatureSample(
                    timestamp: timestamp,
                    serviceIdentifier: service.identifier,
                    product: service.product,
                    rawEventPresent: true,
                    decodedCelsius: nil,
                    finite: false,
                    status: "invalidSample",
                    result: "IOHIDEventGetFloatValue returned non-finite value",
                    timestampSource: "host collection time",
                    error: "NaN or Infinity"
                )
            } else if hidTemperatureIsSentinel(value) {
                sample = HIDTemperatureSample(
                    timestamp: timestamp,
                    serviceIdentifier: service.identifier,
                    product: service.product,
                    rawEventPresent: true,
                    decodedCelsius: nil,
                    finite: true,
                    status: "invalidSample",
                    result: "sentinel temperature value",
                    timestampSource: "host collection time",
                    error: "sentinel value"
                )
            } else if !(HIDProbeConstants.minimumTemperatureCelsius...HIDProbeConstants.maximumTemperatureCelsius).contains(value) {
                sample = HIDTemperatureSample(
                    timestamp: timestamp,
                    serviceIdentifier: service.identifier,
                    product: service.product,
                    rawEventPresent: true,
                    decodedCelsius: nil,
                    finite: true,
                    status: "invalidSample",
                    result: "temperature outside diagnostic range",
                    timestampSource: "host collection time",
                    error: "outside diagnostic range \(HIDProbeConstants.minimumTemperatureCelsius) ... \(HIDProbeConstants.maximumTemperatureCelsius) °C"
                )
            } else {
                sample = HIDTemperatureSample(
                    timestamp: timestamp,
                    serviceIdentifier: service.identifier,
                    product: service.product,
                    rawEventPresent: true,
                    decodedCelsius: value,
                    finite: true,
                    status: "valid",
                    result: "decoded with IOHIDEventGetFloatValue",
                    timestampSource: "host collection time",
                    error: nil
                )
            }
            service.samples.append(sample)
        }

        let wallMilliseconds = (hidMonotonicSeconds() - wallStart) * 1_000
        let cpuMilliseconds = hidProcessCPUSeconds().flatMap { end in
            cpuStart.map { (end - $0) * 1_000 }
        }
        if firstSampleReadWallDurationMilliseconds == 0 {
            firstSampleReadWallDurationMilliseconds = wallMilliseconds
            firstSampleReadCPUTimeMilliseconds = cpuMilliseconds
        } else {
            cachedSampleReadCount += 1
            cachedSampleReadWallDurationMilliseconds += wallMilliseconds
            if let cpuMilliseconds {
                cachedSampleReadCPUTimeMilliseconds = (cachedSampleReadCPUTimeMilliseconds ?? 0) + cpuMilliseconds
            }
        }
        return services.count
    }

    func finalizeDuplicateAnalysis() {
        for leftIndex in services.indices {
            for rightIndex in services.indices where rightIndex > leftIndex {
                let left = services[leftIndex]
                let right = services[rightIndex]
                let leftValues = left.samples.compactMap { $0.status == "valid" ? $0.decodedCelsius : nil }
                let rightValues = right.samples.compactMap { $0.status == "valid" ? $0.decodedCelsius : nil }
                var reason: String?
                var correlation: String?

                if let leftProduct = left.product,
                   let rightProduct = right.product,
                   leftProduct == rightProduct {
                    reason = "same Product string; raw services retained"
                }

                if leftValues.count == rightValues.count,
                   !leftValues.isEmpty,
                   leftValues.count >= 2 {
                    let differences = zip(leftValues, rightValues).map { abs($0 - $1) }
                    if let maximumDifference = differences.max(), maximumDifference <= 0.10 {
                        reason = reason ?? "near-identical valid sample series; duplicate/derived candidate"
                        correlation = String(format: "max absolute difference %.3f °C", maximumDifference)
                    } else if let coefficient = hidPearsonCorrelation(leftValues, rightValues), coefficient >= 0.995 {
                        reason = reason ?? "highly correlated valid sample series; derived/duplicate candidate"
                        correlation = String(format: "Pearson r %.4f", coefficient)
                    }
                }

                guard let reason else { continue }
                left.duplicateCandidates.append(
                    HIDDuplicateCandidate(
                        otherServiceIdentifier: right.identifier,
                        reason: reason,
                        correlation: correlation
                    )
                )
                right.duplicateCandidates.append(
                    HIDDuplicateCandidate(
                        otherServiceIdentifier: left.identifier,
                        reason: reason,
                        correlation: correlation
                    )
                )
            }
        }
    }

    func evidence() -> [HIDTemperatureServiceEvidence] {
        services.map { service in
            HIDTemperatureServiceEvidence(
                id: service.identifier,
                idSource: service.idSource,
                product: service.product,
                properties: service.properties,
                propertyErrors: service.propertyErrors,
                classification: service.classification.category,
                confidence: service.classification.confidence,
                classificationEvidence: service.classification.evidence,
                samples: service.samples,
                statistics: hidTemperatureStatistics(for: service.samples),
                duplicateCandidates: service.duplicateCandidates
            )
        }
    }

    func report() -> HIDBackendReport {
        let performance = HIDPerformanceReport(
            initialDiscoveryWallDurationMilliseconds: discoveryWallDurationMilliseconds,
            initialDiscoveryCPUTimeMilliseconds: discoveryCPUTimeMilliseconds,
            firstSampleReadWallDurationMilliseconds: firstSampleReadWallDurationMilliseconds,
            firstSampleReadCPUTimeMilliseconds: firstSampleReadCPUTimeMilliseconds,
            cachedSampleReadCount: cachedSampleReadCount,
            cachedSampleReadWallDurationMilliseconds: cachedSampleReadWallDurationMilliseconds,
            cachedSampleReadCPUTimeMilliseconds: cachedSampleReadCPUTimeMilliseconds,
            serviceCount: services.count,
            eventReadCount: eventReadCount,
            successfulEventReadCount: successfulEventReadCount,
            failedEventReadCount: failedEventReadCount,
            discoveryStrategy: "discover/cache once; subsequent samples read cached service references"
        )
        return HIDBackendReport(
            available: backendAvailable,
            symbols: symbolAvailability.symbols,
            symbolAvailability: symbolAvailability,
            matching: HIDMatchingReport(
                primaryUsagePage: HIDProbeConstants.primaryUsagePage,
                primaryUsage: HIDProbeConstants.primaryUsage,
                matchingConfigured: matchingConfigured,
                matchingResult: matchingResult,
                discoveryStatus: discoveryStatus,
                discoveryError: discoveryError
            ),
            serviceCount: services.count,
            eventReadCount: eventReadCount,
            successfulEventReadCount: successfulEventReadCount,
            failedEventReadCount: failedEventReadCount,
            errors: errors,
            performance: performance,
            resourceCleanup: HIDResourceCleanupReport(
                serviceArrayReleaseAttempted: serviceArrayReleaseAttempted,
                serviceArrayReleased: serviceArrayReleased,
                clientReleaseAttempted: clientReleaseAttempted,
                clientReleased: clientReleased,
                libraryCloseAttempted: libraryCloseAttempted,
                libraryClosed: libraryClosed
            )
        )
    }

    func close() {
        if serviceArray != nil {
            serviceArrayReleaseAttempted = true
            self.serviceArray = nil
            serviceArrayReleased = true
        }
        if client != nil {
            clientReleaseAttempted = true
            self.client = nil
            clientReleased = true
        }
        if let libraryHandle {
            libraryCloseAttempted = true
            libraryClosed = dlclose(libraryHandle) == 0
            self.libraryHandle = nil
        }
    }

    private func copyPropertyValue(_ service: CFTypeRef, key: String) -> Any? {
        guard let copyProperty,
              let unmanaged = copyProperty(service, key as CFString) else {
            return nil
        }
        return unmanaged.takeRetainedValue()
    }

    private func serviceIdentity(
        properties: [String: HIDPropertyValue],
        index: Int,
        usedIdentifiers: inout Set<String>
    ) -> (identifier: String, source: String) {
        let candidates = ["RegistryID", "IORegistryEntryID", "LocationID", "ServiceID"]
        for key in candidates {
            guard let value = properties[key]?.displayString, !value.isEmpty else { continue }
            let base = "\(key)=\(value)"
            if usedIdentifiers.insert(base).inserted {
                return (base, key)
            }
            let disambiguated = "\(base)#\(index)"
            usedIdentifiers.insert(disambiguated)
            return (disambiguated, "\(key)+enumerationDisambiguator")
        }
        let fallback = "hid-service-index-\(index)"
        usedIdentifiers.insert(fallback)
        return (fallback, "enumerationIndex")
    }

    private static func resolve<T>(
        handle: UnsafeMutableRawPointer?,
        name: String,
        as type: T.Type
    ) -> T? {
        guard let handle else { return nil }
        return name.withCString { symbolName in
            guard let raw = dlsym(handle, symbolName) else { return nil }
            return unsafeBitCast(raw, to: type)
        }
    }
}

private func classifyHIDProduct(_ product: String?) -> HIDSensorClassification {
    guard let product, !product.isEmpty else {
        return HIDSensorClassification(
            category: "unknown",
            confidence: "unknown",
            evidence: "Product property unavailable"
        )
    }

    let lower = product.lowercased()
    if lower.contains("battery") || lower.contains("gas gauge") {
        return HIDSensorClassification(
            category: "battery",
            confidence: "likely",
            evidence: "Product explicitly names a battery/gas-gauge service; numeric correlation is still required for validation"
        )
    }
    if lower.contains("gpu") || lower.contains("pmu2 tdie") || lower.contains("pmu2 tdev") {
        return HIDSensorClassification(
            category: "gpu",
            confidence: "likely",
            evidence: "Product explicitly names GPU; no GPU workload correlation was performed"
        )
    }
    if lower.contains("cpu") || lower.contains("soc") || lower.contains("pmu tdie") || lower.contains("pmu tdev") || lower.contains("pacc") || lower.contains("eacc") {
        return HIDSensorClassification(
            category: "cpu",
            confidence: "likely",
            evidence: "Product is a community CPU/SoC die candidate; no P-core/E-core or exact physical placement is asserted"
        )
    }
    if lower.contains("memory") || lower.contains("dram") || lower.contains("ram") {
        return HIDSensorClassification(
            category: "unknown",
            confidence: "unknown",
            evidence: "Product mentions memory, but this probe cannot prove RAM/DRAM junction temperature"
        )
    }
    if lower.contains("nand") || lower.contains("ssd") || lower.contains("storage") {
        return HIDSensorClassification(
            category: "unknown",
            confidence: "unknown",
            evidence: "Product mentions storage, but this probe cannot prove NAND temperature"
        )
    }
    if lower.contains("cal") || lower.contains("calibration") || lower.contains("virtual") || lower.contains("average") {
        return HIDSensorClassification(
            category: "unknown",
            confidence: "unknown",
            evidence: "Product suggests calibration/derived/virtual behavior; physical placement is unvalidated"
        )
    }
    return HIDSensorClassification(
        category: "unknown",
        confidence: "unknown",
        evidence: "No validated category mapping for this Product string"
    )
}

private func hidTemperatureIsSentinel(_ value: Double) -> Bool {
    [-273.15, -127, -128, 127, 255, 65_535].contains(value)
}

private func hidTemperatureStatistics(for samples: [HIDTemperatureSample]) -> HIDTemperatureStatistics? {
    let validValues = samples.compactMap { sample -> Double? in
        guard sample.status == "valid", let value = sample.decodedCelsius else { return nil }
        return value
    }
    guard !samples.isEmpty else { return nil }

    let first = validValues.first
    let last = validValues.last
    let average = validValues.isEmpty ? nil : validValues.reduce(0, +) / Double(validValues.count)
    let standardDeviation: Double?
    if let average, !validValues.isEmpty {
        let variance = validValues.reduce(0.0) { partial, value in
            let difference = value - average
            return partial + difference * difference
        } / Double(validValues.count)
        standardDeviation = sqrt(variance)
    } else {
        standardDeviation = nil
    }
    return HIDTemperatureStatistics(
        sampleCount: samples.count,
        validSampleCount: validValues.count,
        invalidSampleCount: samples.count - validValues.count,
        first: first,
        last: last,
        minimum: validValues.min(),
        average: average,
        maximum: validValues.max(),
        delta: first.flatMap { firstValue in last.map { $0 - firstValue } },
        standardDeviation: standardDeviation
    )
}

private func hidPearsonCorrelation(_ lhs: [Double], _ rhs: [Double]) -> Double? {
    guard lhs.count == rhs.count, lhs.count >= 2 else { return nil }
    let lhsAverage = lhs.reduce(0, +) / Double(lhs.count)
    let rhsAverage = rhs.reduce(0, +) / Double(rhs.count)
    var numerator = 0.0
    var lhsVariance = 0.0
    var rhsVariance = 0.0
    for (left, right) in zip(lhs, rhs) {
        let leftDifference = left - lhsAverage
        let rightDifference = right - rhsAverage
        numerator += leftDifference * rightDifference
        lhsVariance += leftDifference * leftDifference
        rhsVariance += rightDifference * rightDifference
    }
    let denominator = sqrt(lhsVariance * rhsVariance)
    guard denominator > 0 else { return nil }
    return numerator / denominator
}

private func hidMonotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}

private func hidProcessCPUSeconds() -> Double? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return user + system
}
