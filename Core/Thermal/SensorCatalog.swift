import Foundation

struct MacOSBuildRange: Sendable, Equatable, Codable, Hashable {
    let minimum: String?
    let maximum: String?

    init(minimum: String? = nil, maximum: String? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }

    func contains(_ build: String) -> Bool {
        if let minimum, build.compare(minimum, options: [.numeric, .caseInsensitive]) == .orderedAscending {
            return false
        }
        if let maximum, build.compare(maximum, options: [.numeric, .caseInsensitive]) == .orderedDescending {
            return false
        }
        return true
    }
}

struct SensorValidationReference: Sendable, Equatable, Codable, Hashable {
    let identifier: String
    let detail: String

    init(identifier: String, detail: String = "") {
        self.identifier = identifier
        self.detail = detail
    }

    init(_ identifier: String, detail: String = "") {
        self.init(identifier: identifier, detail: detail)
    }
}

struct SensorCatalogEntry: Sendable, Equatable, Codable, Hashable {
    let id: String
    let source: TemperatureSensorSource
    let modelIdentifier: String?
    let socFamily: String?
    let macOSBuildRange: MacOSBuildRange?
    let rawIdentifierPattern: String?
    let rawNamePattern: String?
    let requiredServiceClass: String?
    let mapping: SensorMapping
    let explicitPriority: Int
    let provenance: [SensorValidationReference]

    init(
        id: String,
        source: TemperatureSensorSource,
        modelIdentifier: String? = nil,
        socFamily: String? = nil,
        macOSBuildRange: MacOSBuildRange? = nil,
        rawIdentifierPattern: String? = nil,
        rawNamePattern: String? = nil,
        requiredServiceClass: String? = nil,
        mapping: SensorMapping,
        explicitPriority: Int = 0,
        provenance: [SensorValidationReference] = []
    ) {
        self.id = id
        self.source = source
        self.modelIdentifier = modelIdentifier
        self.socFamily = socFamily
        self.macOSBuildRange = macOSBuildRange
        self.rawIdentifierPattern = rawIdentifierPattern
        self.rawNamePattern = rawNamePattern
        self.requiredServiceClass = requiredServiceClass
        self.mapping = mapping
        self.explicitPriority = explicitPriority
        self.provenance = provenance
    }

    func matches(
        identity: SensorIdentity,
        socFamily: String? = nil,
        macOSBuild: String? = nil
    ) -> Bool {
        guard source == identity.source else { return false }

        if let modelIdentifier,
           identity.modelIdentifier != modelIdentifier {
            return false
        }

        if let requiredSocFamily = self.socFamily {
            guard socFamily == requiredSocFamily else { return false }
        }

        if let macOSBuildRange {
            guard let macOSBuild, macOSBuildRange.contains(macOSBuild) else { return false }
        }

        if let requiredServiceClass,
           identity.serviceClass != requiredServiceClass {
            return false
        }

        if let rawIdentifierPattern,
           !Self.matches(pattern: rawIdentifierPattern, value: identity.rawIdentifier) {
            return false
        }

        if let rawNamePattern {
            guard let rawName = identity.rawName,
                  Self.matches(pattern: rawNamePattern, value: rawName) else {
                return false
            }
        }

        return true
    }

    private static func matches(pattern: String, value: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Runtime code receives a value copy of this catalog. No sample can mutate it.
struct SensorCatalog: Sendable, Equatable, Codable {
    let entries: [SensorCatalogEntry]

    init(_ entries: [SensorCatalogEntry]) {
        self.init(entries: entries)
    }

    init(entries: [SensorCatalogEntry]) {
        self.entries = entries.sorted {
            if $0.explicitPriority != $1.explicitPriority {
                return $0.explicitPriority > $1.explicitPriority
            }
            return $0.id < $1.id
        }
    }

    func entries(
        matching identity: SensorIdentity,
        socFamily: String? = nil,
        macOSBuild: String? = nil
    ) -> [SensorCatalogEntry] {
        entries.filter {
            $0.matches(identity: identity, socFamily: socFamily, macOSBuild: macOSBuild)
        }
    }

    func entries(for category: TemperatureSensorCategory) -> [SensorCatalogEntry] {
        entries.filter { $0.mapping.category == category }
    }

    func entry(id: String) -> SensorCatalogEntry? {
        entries.first { $0.id == id }
    }

    func mapping(
        for identity: SensorIdentity,
        socFamily: String? = nil,
        macOSBuild: String? = nil
    ) -> SensorMapping? {
        entries(matching: identity, socFamily: socFamily, macOSBuild: macOSBuild).first?.mapping
    }

    static let m4Initial = SensorCatalog(entries: [
        SensorCatalogEntry(
            id: "iohid.storage.nand-ch0",
            source: .ioHID,
            rawNamePattern: "(?i)^NAND CH0 temp$",
            requiredServiceClass: "AppleEmbeddedNVMeTemperatureSensor",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.storage.nand-ch0",
                category: .storage,
                confidence: .high,
                displayName: "Internal storage sensor",
                aggregationGroup: "internal-storage",
                aggregationRole: .canonicalStorage
            ),
            explicitPriority: 100,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "AppleEmbeddedNVMeTemperatureSensor / NAND CH0 temp"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "iohid.battery.gas-gauge",
            source: .ioHID,
            rawNamePattern: "(?i)^gas gauge battery$",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.battery.gas-gauge",
                category: .battery,
                confidence: .high,
                displayName: "Battery sensor",
                aggregationGroup: "battery",
                aggregationRole: .canonicalBattery
            ),
            explicitPriority: 100,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "gas gauge battery HID value correlated with AppleSmartBattery"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "iohid.pmu.tdie",
            source: .ioHID,
            rawNamePattern: "(?i)^PMU tdie.*$",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.pmu.tdie",
                category: .pmu,
                confidence: .medium,
                displayName: "PMU die sensor",
                aggregationGroup: "pmu",
                aggregationRole: .contextOnly
            ),
            explicitPriority: 40,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "PMU tdie* is retained as PMU diagnostic context"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "iohid.pmu2.tdie",
            source: .ioHID,
            rawNamePattern: "(?i)^PMU2 tdie.*$",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.pmu2.tdie",
                category: .pmu,
                confidence: .medium,
                displayName: "PMU2 die sensor",
                aggregationGroup: "pmu2",
                aggregationRole: .contextOnly
            ),
            explicitPriority: 40,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "PMU2 tdie* is retained as PMU diagnostic context"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "iohid.pmu.tdev",
            source: .ioHID,
            rawNamePattern: "(?i)^PMU tdev.*$",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.pmu.tdev",
                category: .pmu,
                confidence: .medium,
                displayName: "PMU device sensor",
                aggregationGroup: "pmu",
                aggregationRole: .contextOnly
            ),
            explicitPriority: 35,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "PMU tdev* is retained as PMU diagnostic context"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "iohid.pmu2.tdev",
            source: .ioHID,
            rawNamePattern: "(?i)^PMU2 tdev.*$",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.pmu2.tdev",
                category: .pmu,
                confidence: .medium,
                displayName: "PMU2 device sensor",
                aggregationGroup: "pmu2",
                aggregationRole: .contextOnly
            ),
            explicitPriority: 35,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "PMU2 tdev* is retained as PMU diagnostic context"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "iohid.ambient.als-temp",
            source: .ioHID,
            rawNamePattern: "(?i)^als-temp$",
            mapping: SensorMapping(
                status: .mapped,
                catalogID: "iohid.ambient.als-temp",
                category: .ambient,
                confidence: .medium,
                displayName: "Ambient sensor",
                aggregationGroup: "ambient",
                aggregationRole: .contextOnly
            ),
            explicitPriority: 30,
            provenance: [
                SensorValidationReference(
                    "M4 HID differential summary",
                    detail: "als-temp is retained as ambient diagnostic context"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "smc.cpu.tp-candidate",
            source: .appleSMC,
            rawIdentifierPattern: "(?i)^Tp.*$",
            mapping: SensorMapping(
                status: .candidate,
                catalogID: "smc.cpu.tp-candidate",
                category: .cpu,
                confidence: .medium,
                displayName: "SMC CPU candidate",
                aggregationGroup: nil,
                aggregationRole: .none
            ),
            explicitPriority: 20,
            provenance: [
                SensorValidationReference(
                    "M4 AppleSMC evidence",
                    detail: "Tp* prefix alone does not prove CPU semantics"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "smc.gpu.tg-candidate",
            source: .appleSMC,
            rawIdentifierPattern: "(?i)^Tg.*$",
            mapping: SensorMapping(
                status: .candidate,
                catalogID: "smc.gpu.tg-candidate",
                category: .gpu,
                confidence: .medium,
                displayName: "SMC GPU candidate",
                aggregationGroup: nil,
                aggregationRole: .none
            ),
            explicitPriority: 20,
            provenance: [
                SensorValidationReference(
                    "M4 AppleSMC evidence",
                    detail: "Tg* prefix alone does not prove GPU semantics"
                )
            ]
        ),
        SensorCatalogEntry(
            id: "smc.memory.tm-candidate",
            source: .appleSMC,
            rawIdentifierPattern: "(?i)^Tm.*$",
            mapping: SensorMapping(
                status: .candidate,
                catalogID: "smc.memory.tm-candidate",
                category: .memory,
                confidence: .low,
                displayName: "SMC memory candidate",
                aggregationGroup: nil,
                aggregationRole: .none
            ),
            explicitPriority: 10,
            provenance: [
                SensorValidationReference(
                    "M4 AppleSMC evidence",
                    detail: "Tm* prefix alone does not prove RAM temperature"
                )
            ]
        )
    ])

    static let initial = m4Initial
}
