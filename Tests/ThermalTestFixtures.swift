import Foundation

struct FakeThermalBackend: Sendable, Equatable {
    let source: TemperatureSensorSource
    let status: TemperatureBackendStatus
    let readings: [TemperatureSensorReading]

    init(
        source: TemperatureSensorSource,
        status: TemperatureBackendStatus,
        readings: [TemperatureSensorReading] = []
    ) {
        self.source = source
        self.status = status
        self.readings = readings
    }
}

enum ThermalTestFixtures {
    static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    static func identity(
        source: TemperatureSensorSource,
        rawIdentifier: String,
        rawName: String? = nil,
        serviceClass: String? = nil,
        modelIdentifier: String? = nil
    ) -> SensorIdentity {
        SensorIdentity(
            source: source,
            rawIdentifier: rawIdentifier,
            rawName: rawName,
            serviceClass: serviceClass,
            modelIdentifier: modelIdentifier
        )
    }

    static func mapping(
        status: SensorMappingStatus = .mapped,
        catalogID: String? = nil,
        category: TemperatureSensorCategory,
        confidence: SensorConfidence,
        displayName: String? = nil,
        aggregationGroup: String? = nil,
        aggregationRole: TemperatureAggregationRole
    ) -> SensorMapping {
        SensorMapping(
            status: status,
            catalogID: catalogID,
            category: category,
            confidence: confidence,
            displayName: displayName,
            aggregationGroup: aggregationGroup,
            aggregationRole: aggregationRole
        )
    }

    static func reading(
        source: TemperatureSensorSource,
        rawIdentifier: String,
        rawName: String? = nil,
        mapping: SensorMapping,
        sample: TemperatureSample,
        hardwareEpoch: UInt64 = 1,
        serviceClass: String? = nil
    ) -> TemperatureSensorReading {
        TemperatureSensorReading(
            identity: identity(
                source: source,
                rawIdentifier: rawIdentifier,
                rawName: rawName,
                serviceClass: serviceClass
            ),
            mapping: mapping,
            sample: sample,
            timestamp: timestamp,
            hardwareEpoch: hardwareEpoch
        )
    }

    static func selection(
        category: TemperatureSensorCategory,
        source: TemperatureSensorSource?,
        catalogEntryIDs: [String] = [],
        confidence: SensorConfidence? = nil,
        generation: UInt64 = 1,
        reason: CategorySelectionReason = .selectedBySemanticConfidence
    ) -> TemperatureCategorySourceSelection {
        TemperatureCategorySourceSelection(
            category: category,
            source: source,
            catalogEntryIDs: catalogEntryIDs,
            semanticConfidence: confidence,
            selectionGeneration: generation,
            reason: reason
        )
    }

    static func catalogEntry(
        id: String,
        source: TemperatureSensorSource,
        category: TemperatureSensorCategory,
        confidence: SensorConfidence,
        status: SensorMappingStatus = .mapped,
        role: TemperatureAggregationRole,
        aggregationGroup: String? = nil,
        priority: Int = 0,
        rawIdentifierPattern: String? = nil,
        rawNamePattern: String? = nil,
        requiredServiceClass: String? = nil
    ) -> SensorCatalogEntry {
        SensorCatalogEntry(
            id: id,
            source: source,
            rawIdentifierPattern: rawIdentifierPattern,
            rawNamePattern: rawNamePattern,
            requiredServiceClass: requiredServiceClass,
            mapping: mapping(
                status: status,
                catalogID: id,
                category: category,
                confidence: confidence,
                aggregationGroup: aggregationGroup,
                aggregationRole: role
            ),
            explicitPriority: priority
        )
    }

    static func backendStatus(
        _ source: TemperatureSensorSource,
        availability: TemperatureBackendAvailability = .available,
        runtimeHealth: BackendRuntimeHealth = .empty
    ) -> TemperatureBackendStatus {
        TemperatureBackendStatus(
            source: source,
            availability: availability,
            runtimeHealth: runtimeHealth
        )
    }
}
