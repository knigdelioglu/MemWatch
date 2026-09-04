import Foundation

enum TemperatureSensorSource: String, Sendable, Hashable, Codable {
    case ioHID
    case appleSMC
}

enum TemperatureSensorCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case cpu
    case gpu
    case soc
    case memory
    case memoryController
    case battery
    case storage
    case pmu
    case ambient
    case enclosure
    case unknown

    var isUserFacingAggregate: Bool {
        switch self {
        case .cpu, .gpu, .soc, .memory, .memoryController, .battery, .storage:
            return true
        case .pmu, .ambient, .enclosure, .unknown:
            return false
        }
    }
}

enum SensorConfidence: Int, Comparable, Sendable, Hashable, Codable {
    case unknown = 0
    case low = 1
    case medium = 2
    case high = 3
    case validated = 4

    static func < (lhs: SensorConfidence, rhs: SensorConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Stable hardware identity. A measured value is deliberately not part of it.
struct SensorIdentity: Hashable, Sendable, Codable {
    let source: TemperatureSensorSource
    let rawIdentifier: String
    let rawName: String?
    let serviceClass: String?
    let modelIdentifier: String?

    init(
        source: TemperatureSensorSource,
        rawIdentifier: String,
        rawName: String? = nil,
        serviceClass: String? = nil,
        modelIdentifier: String? = nil
    ) {
        self.source = source
        self.rawIdentifier = rawIdentifier
        self.rawName = rawName
        self.serviceClass = serviceClass
        self.modelIdentifier = modelIdentifier
    }
}

enum SensorMappingStatus: String, Sendable, Equatable, Hashable, Codable {
    case mapped
    case candidate
    case unmapped
}

enum TemperatureAggregationRole: String, Sendable, Equatable, Hashable, Codable {
    case none
    case cpuPackage
    case cpuClusterMember
    case gpuPackage
    case gpuClusterMember
    case canonicalBattery
    case canonicalStorage
    case contextOnly
}

struct SensorMapping: Sendable, Equatable, Hashable, Codable {
    let status: SensorMappingStatus
    let catalogID: String?
    let category: TemperatureSensorCategory?
    let confidence: SensorConfidence
    let displayName: String?
    let aggregationGroup: String?
    let aggregationRole: TemperatureAggregationRole

    init(
        status: SensorMappingStatus,
        catalogID: String? = nil,
        category: TemperatureSensorCategory? = nil,
        confidence: SensorConfidence = .unknown,
        displayName: String? = nil,
        aggregationGroup: String? = nil,
        aggregationRole: TemperatureAggregationRole = .none
    ) {
        self.status = status
        self.catalogID = catalogID
        self.category = category
        self.confidence = confidence
        self.displayName = displayName
        self.aggregationGroup = aggregationGroup
        self.aggregationRole = aggregationRole
    }
}

enum TemperatureSampleStatus: String, Sendable, Equatable, Hashable, Codable {
    case valid
    case readFailed
    case invalidSample
    case stale
    case notSampled
}

/// Measurement outcome and measurement quality are one source of truth.
/// Mapping state lives separately in SensorMapping.
enum TemperatureSample: Sendable, Equatable {
    case valid(celsius: Double)
    case readFailed(code: String?)
    case invalidSample(reason: String)
    case stale(lastKnownCelsius: Double?, age: TimeInterval)
    case notSampled

    var status: TemperatureSampleStatus {
        switch self {
        case .valid:
            return .valid
        case .readFailed:
            return .readFailed
        case .invalidSample:
            return .invalidSample
        case .stale:
            return .stale
        case .notSampled:
            return .notSampled
        }
    }

    var validCelsius: Double? {
        guard case let .valid(celsius) = self else { return nil }
        return celsius
    }
}

struct TemperatureSensorReading: Sendable, Equatable {
    let identity: SensorIdentity
    let mapping: SensorMapping
    let sample: TemperatureSample
    let timestamp: Date
    let hardwareEpoch: UInt64

    init(
        identity: SensorIdentity,
        mapping: SensorMapping,
        sample: TemperatureSample,
        timestamp: Date = Date(),
        hardwareEpoch: UInt64
    ) {
        self.identity = identity
        self.mapping = mapping
        self.sample = sample
        self.timestamp = timestamp
        self.hardwareEpoch = hardwareEpoch
    }

    var source: TemperatureSensorSource {
        identity.source
    }

    var status: TemperatureSampleStatus {
        sample.status
    }
}
