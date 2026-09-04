import Foundation

enum CategorySelectionReason: String, Sendable, Equatable, Hashable, Codable {
    case noRelevantMapping
    case categoryUnavailable
    case backendUnavailable
    case selectedBySemanticConfidence
    case selectedByExplicitPriority
    case retainedCurrentSource
    case deterministicTieBreak
}

struct TemperatureCategorySourceSelection: Sendable, Equatable, Codable {
    let category: TemperatureSensorCategory
    let source: TemperatureSensorSource?
    let catalogEntryIDs: [String]
    let semanticConfidence: SensorConfidence?
    let selectionGeneration: UInt64
    let reason: CategorySelectionReason

    init(
        category: TemperatureSensorCategory,
        source: TemperatureSensorSource?,
        catalogEntryIDs: [String] = [],
        semanticConfidence: SensorConfidence? = nil,
        selectionGeneration: UInt64 = 0,
        reason: CategorySelectionReason
    ) {
        self.category = category
        self.source = source
        self.catalogEntryIDs = Array(Set(catalogEntryIDs)).sorted()
        self.semanticConfidence = semanticConfidence
        self.selectionGeneration = selectionGeneration
        self.reason = reason
    }

    var isSelected: Bool {
        source != nil
    }
}

struct ThermalCategorySourceSelections: Sendable, Equatable, Codable {
    let selections: [TemperatureCategorySourceSelection]

    init(_ selections: [TemperatureCategorySourceSelection] = []) {
        var byCategory: [TemperatureSensorCategory: TemperatureCategorySourceSelection] = [:]
        for selection in selections {
            byCategory[selection.category] = selection
        }
        self.selections = TemperatureSensorCategory.allCases.compactMap { byCategory[$0] }
    }

    init(selections: [TemperatureCategorySourceSelection]) {
        self.init(selections)
    }

    static let empty = ThermalCategorySourceSelections()

    func selection(for category: TemperatureSensorCategory) -> TemperatureCategorySourceSelection? {
        selections.first { $0.category == category }
    }

    func source(for category: TemperatureSensorCategory) -> TemperatureSensorSource? {
        selection(for: category)?.source
    }

    subscript(category: TemperatureSensorCategory) -> TemperatureCategorySourceSelection? {
        selection(for: category)
    }
}

struct ThermalSourcePolicyDecision: Sendable, Equatable {
    let selections: ThermalCategorySourceSelections
    let selectionGeneration: UInt64
    let changedCategories: Set<TemperatureSensorCategory>

    var didChange: Bool {
        !changedCategories.isEmpty
    }
}

/// Selects one canonical source independently for every sensor category.
/// It intentionally has no temperature-value input: values cannot influence
/// source selection and there is no global active backend.
struct ThermalSourcePolicy: Sendable {
    private struct Candidate: Sendable {
        let source: TemperatureSensorSource
        let entries: [SensorCatalogEntry]
        let semanticConfidence: SensorConfidence
        let explicitPriority: Int
    }

    func select(
        backendStatuses: ThermalBackendStatuses,
        catalogEntries: [SensorCatalogEntry],
        categoryAvailability: ThermalCategoryAvailabilityReport = .empty,
        currentSelections: ThermalCategorySourceSelections = .empty,
        selectionGeneration: UInt64 = 0
    ) -> ThermalCategorySourceSelections {
        evaluate(
            backendStatuses: backendStatuses,
            catalogEntries: catalogEntries,
            categoryAvailability: categoryAvailability,
            currentSelections: currentSelections,
            selectionGeneration: selectionGeneration
        ).selections
    }

    func evaluate(
        backendStatuses: ThermalBackendStatuses,
        catalogEntries: [SensorCatalogEntry],
        categoryAvailability: ThermalCategoryAvailabilityReport = .empty,
        currentSelections: ThermalCategorySourceSelections = .empty,
        selectionGeneration: UInt64 = 0
    ) -> ThermalSourcePolicyDecision {
        let provisionalSelections = TemperatureSensorCategory.allCases.map { category in
            provisionalSelection(
                for: category,
                backendStatuses: backendStatuses,
                catalogEntries: catalogEntries,
                categoryAvailability: categoryAvailability,
                currentSelections: currentSelections
            )
        }

        let changedCategories = Set(
            provisionalSelections.compactMap { selection -> TemperatureSensorCategory? in
                guard let current = currentSelections.selection(for: selection.category) else {
                    return selection.source == nil ? nil : selection.category
                }
                return isSameCanonicalChoice(current, selection) ? nil : selection.category
            }
        )
        let nextGeneration = changedCategories.isEmpty ? selectionGeneration : selectionGeneration &+ 1
        let selections = ThermalCategorySourceSelections(
            provisionalSelections.map { selection in
                TemperatureCategorySourceSelection(
                    category: selection.category,
                    source: selection.source,
                    catalogEntryIDs: selection.catalogEntryIDs,
                    semanticConfidence: selection.semanticConfidence,
                    selectionGeneration: nextGeneration,
                    reason: selection.reason
                )
            }
        )

        return ThermalSourcePolicyDecision(
            selections: selections,
            selectionGeneration: nextGeneration,
            changedCategories: changedCategories
        )
    }

    func evaluate(
        backendStatuses: ThermalBackendStatuses,
        catalog: SensorCatalog,
        categoryAvailability: ThermalCategoryAvailabilityReport = .empty,
        currentSelections: ThermalCategorySourceSelections = .empty,
        selectionGeneration: UInt64 = 0
    ) -> ThermalSourcePolicyDecision {
        evaluate(
            backendStatuses: backendStatuses,
            catalogEntries: catalog.entries,
            categoryAvailability: categoryAvailability,
            currentSelections: currentSelections,
            selectionGeneration: selectionGeneration
        )
    }

    private func provisionalSelection(
        for category: TemperatureSensorCategory,
        backendStatuses: ThermalBackendStatuses,
        catalogEntries: [SensorCatalogEntry],
        categoryAvailability: ThermalCategoryAvailabilityReport,
        currentSelections: ThermalCategorySourceSelections
    ) -> TemperatureCategorySourceSelection {
        if categoryAvailability.hasExplicitStatus(for: category),
           !allowsSelection(for: categoryAvailability.status(for: category)) {
            return TemperatureCategorySourceSelection(
                category: category,
                source: nil,
                reason: .categoryUnavailable
            )
        }

        let relevantEntries = catalogEntries.filter {
            $0.mapping.status == .mapped && $0.mapping.category == category
        }
        guard !relevantEntries.isEmpty else {
            return TemperatureCategorySourceSelection(
                category: category,
                source: nil,
                reason: .noRelevantMapping
            )
        }

        let candidates = Dictionary(grouping: relevantEntries, by: \.source).compactMap { source, entries -> Candidate? in
            guard backendStatuses[source]?.availability.isSelectable == true else { return nil }
            let semanticConfidence = entries.map(\.mapping.confidence).max() ?? .unknown
            let bestConfidenceEntries = entries.filter { $0.mapping.confidence == semanticConfidence }
            let explicitPriority = bestConfidenceEntries.map(\.explicitPriority).max() ?? 0
            return Candidate(
                source: source,
                entries: entries.sorted {
                    if $0.explicitPriority != $1.explicitPriority {
                        return $0.explicitPriority > $1.explicitPriority
                    }
                    return $0.id < $1.id
                },
                semanticConfidence: semanticConfidence,
                explicitPriority: explicitPriority
            )
        }

        guard !candidates.isEmpty else {
            return TemperatureCategorySourceSelection(
                category: category,
                source: nil,
                reason: .backendUnavailable
            )
        }

        let bestConfidence = candidates.map(\.semanticConfidence).max() ?? .unknown
        let confidenceWinners = candidates.filter { $0.semanticConfidence == bestConfidence }
        let bestPriority = confidenceWinners.map(\.explicitPriority).max() ?? 0
        let qualityWinners = confidenceWinners.filter { $0.explicitPriority == bestPriority }

        let currentCandidate = currentSelections[category].flatMap { current in
            current.source.flatMap { source in candidates.first { $0.source == source } }
        }
        guard let bestCandidate = qualityWinners.sorted(by: deterministicCandidateOrder).first else {
            return TemperatureCategorySourceSelection(
                category: category,
                source: nil,
                reason: .backendUnavailable
            )
        }
        let chosen: Candidate
        let reason: CategorySelectionReason

        if let currentCandidate,
           let currentSource = currentSelections[category]?.source,
           backendStatuses[currentSource]?.availability == .available,
           currentCandidate.semanticConfidence == bestCandidate.semanticConfidence,
           currentCandidate.explicitPriority == bestCandidate.explicitPriority {
            chosen = currentCandidate
            reason = .retainedCurrentSource
        } else {
            chosen = bestCandidate
            reason = reasonForNewChoice(
                chosen: chosen,
                candidates: candidates,
                current: currentCandidate,
                qualityWinnerCount: qualityWinners.count
            )
        }

        return TemperatureCategorySourceSelection(
            category: category,
            source: chosen.source,
            catalogEntryIDs: chosen.entries.map(\.id),
            semanticConfidence: chosen.semanticConfidence,
            reason: reason
        )
    }

    private func allowsSelection(for availability: TemperatureCategoryAvailability) -> Bool {
        switch availability {
        case .available, .degraded, .notSampled:
            return true
        case .temporarilyUnavailable, .unmapped:
            return false
        }
    }

    private func reasonForNewChoice(
        chosen: Candidate,
        candidates: [Candidate],
        current: Candidate?,
        qualityWinnerCount: Int
    ) -> CategorySelectionReason {
        if let current {
            if chosen.semanticConfidence > current.semanticConfidence {
                return .selectedBySemanticConfidence
            }
            if chosen.explicitPriority > current.explicitPriority {
                return .selectedByExplicitPriority
            }
        }

        let otherCandidates = candidates.filter { $0.source != chosen.source }
        if otherCandidates.contains(where: { $0.semanticConfidence < chosen.semanticConfidence }) {
            return .selectedBySemanticConfidence
        }
        if otherCandidates.contains(where: { $0.semanticConfidence == chosen.semanticConfidence && $0.explicitPriority < chosen.explicitPriority }) {
            return .selectedByExplicitPriority
        }
        return qualityWinnerCount > 1 ? .deterministicTieBreak : .selectedBySemanticConfidence
    }

    private func deterministicCandidateOrder(lhs: Candidate, rhs: Candidate) -> Bool {
        lhs.source.rawValue < rhs.source.rawValue
    }

    private func isSameCanonicalChoice(
        _ lhs: TemperatureCategorySourceSelection,
        _ rhs: TemperatureCategorySourceSelection
    ) -> Bool {
        lhs.source == rhs.source
            && lhs.catalogEntryIDs == rhs.catalogEntryIDs
            && lhs.semanticConfidence == rhs.semanticConfidence
    }
}
