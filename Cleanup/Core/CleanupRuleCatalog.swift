import Foundation

enum CleanupRootPolicy: Equatable, Sendable {
    case userHome
    case userLibrary
    case temporaryDirectory
    case systemLibrary
    case privateVar
    case requestedRoots
}

struct CleanupRule: Equatable, Sendable {
    let id: CleanupRuleID
    let category: CleanupCategory
    let rootPolicy: CleanupRootPolicy
    let defaultSafety: CleanupSafetyLevel
    let deletionMode: CleanupDeletionMode
    let requirements: CleanupRequirements
    let minimumAge: TimeInterval?
    let description: String

    init(
        id: CleanupRuleID,
        category: CleanupCategory,
        rootPolicy: CleanupRootPolicy,
        defaultSafety: CleanupSafetyLevel,
        deletionMode: CleanupDeletionMode,
        requirements: CleanupRequirements = [],
        minimumAge: TimeInterval? = nil,
        description: String
    ) {
        self.id = id
        self.category = category
        self.rootPolicy = rootPolicy
        self.defaultSafety = defaultSafety
        self.deletionMode = deletionMode
        self.requirements = requirements
        self.minimumAge = minimumAge
        self.description = description
    }
}

struct CleanupRuleCatalog: Sendable {
    private let rules: [CleanupRuleID: CleanupRule]

    init(rules: [CleanupRule] = Self.defaultRules) {
        var map: [CleanupRuleID: CleanupRule] = [:]
        for rule in rules {
            precondition(map[rule.id] == nil, "Duplicate cleanup rule ID: \(rule.id.rawValue)")
            map[rule.id] = rule
        }
        self.rules = map
    }

    func rule(for id: CleanupRuleID) -> CleanupRule? {
        rules[id]
    }

    var allRules: [CleanupRule] {
        Array(rules.values)
    }

    static let defaultRules: [CleanupRule] = [
        CleanupRule(
            id: "user.cache",
            category: .userCaches,
            rootPolicy: .userLibrary,
            defaultSafety: .safe,
            deletionMode: .permanent,
            description: "Regenerable user application cache"
        ),
        CleanupRule(
            id: "user.log.old",
            category: .logs,
            rootPolicy: .userLibrary,
            defaultSafety: .safe,
            deletionMode: .permanent,
            minimumAge: 30 * 24 * 60 * 60,
            description: "Old user log file"
        ),
        CleanupRule(
            id: "system.cache",
            category: .systemCaches,
            rootPolicy: .systemLibrary,
            defaultSafety: .review,
            deletionMode: .privileged,
            requirements: [.privilegedHelper],
            description: "System-wide cache approved by a typed privileged rule"
        ),
        CleanupRule(
            id: "system.log.old",
            category: .logs,
            rootPolicy: .systemLibrary,
            defaultSafety: .review,
            deletionMode: .privileged,
            requirements: [.privilegedHelper],
            minimumAge: 30 * 24 * 60 * 60,
            description: "Old system-wide log"
        ),
        CleanupRule(
            id: "privatevar.temp.old",
            category: .systemCaches,
            rootPolicy: .privateVar,
            defaultSafety: .review,
            deletionMode: .privileged,
            requirements: [.privilegedHelper],
            minimumAge: 7 * 24 * 60 * 60,
            description: "Old temporary data under an explicitly allowed private/var root"
        ),
        CleanupRule(
            id: "xcode.deriveddata",
            category: .xcode,
            rootPolicy: .userLibrary,
            defaultSafety: .safe,
            deletionMode: .permanent,
            requirements: [.applicationInactive],
            description: "Xcode DerivedData that can be regenerated"
        ),
        CleanupRule(
            id: "xcode.modulecache",
            category: .xcode,
            rootPolicy: .userLibrary,
            defaultSafety: .safe,
            deletionMode: .permanent,
            requirements: [.applicationInactive],
            description: "Xcode module cache that can be regenerated"
        ),
        CleanupRule(
            id: "xcode.documentationcache",
            category: .xcode,
            rootPolicy: .userLibrary,
            defaultSafety: .safe,
            deletionMode: .permanent,
            requirements: [.applicationInactive],
            description: "Xcode documentation cache"
        ),
        CleanupRule(
            id: "xcode.devicesupport",
            category: .xcode,
            rootPolicy: .userLibrary,
            defaultSafety: .review,
            deletionMode: .permanent,
            requirements: [.explicitConfirmation, .applicationInactive],
            description: "Xcode device support files; removing them may require a later download"
        ),
        CleanupRule(
            id: "developer.cache",
            category: .developer,
            rootPolicy: .userHome,
            defaultSafety: .safe,
            deletionMode: .permanent,
            description: "Regenerable developer-tool cache"
        ),
        CleanupRule(
            id: "project.artifact",
            category: .projectArtifacts,
            rootPolicy: .requestedRoots,
            defaultSafety: .review,
            deletionMode: .permanent,
            requirements: [.explicitConfirmation],
            description: "Regenerable project dependency or build artifact"
        ),
        CleanupRule(
            id: "ai.cache",
            category: .aiArtifacts,
            rootPolicy: .userHome,
            defaultSafety: .safe,
            deletionMode: .permanent,
            description: "AI tool cache that is not a model weight or user data"
        ),
        CleanupRule(
            id: "ai.model",
            category: .aiArtifacts,
            rootPolicy: .userHome,
            defaultSafety: .protected,
            deletionMode: .none,
            description: "Downloaded local model; visible for management but excluded from cleanup"
        ),
        CleanupRule(
            id: "application.leftover.user",
            category: .applicationLeftovers,
            rootPolicy: .userLibrary,
            defaultSafety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            description: "High-confidence leftover belonging to an uninstalled application"
        ),
        CleanupRule(
            id: "application.leftover.system",
            category: .applicationLeftovers,
            rootPolicy: .systemLibrary,
            defaultSafety: .review,
            deletionMode: .privileged,
            requirements: [.privilegedHelper, .explicitConfirmation],
            description: "High-confidence system-wide leftover belonging to an uninstalled application"
        ),
        CleanupRule(
            id: "launchitem.orphan",
            category: .launchItems,
            rootPolicy: .systemLibrary,
            defaultSafety: .review,
            deletionMode: .privileged,
            requirements: [.privilegedHelper, .explicitConfirmation],
            description: "Launch item whose owning application and executable are both absent"
        ),
        CleanupRule(
            id: "ios.backup",
            category: .iosBackups,
            rootPolicy: .userLibrary,
            defaultSafety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            description: "Local Apple-device backup"
        ),
        CleanupRule(
            id: "downloads.review",
            category: .downloads,
            rootPolicy: .userHome,
            defaultSafety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            description: "Download or installer selected for user review"
        ),
        CleanupRule(
            id: "trash.user",
            category: .trash,
            rootPolicy: .userHome,
            defaultSafety: .review,
            deletionMode: .permanent,
            requirements: [.explicitConfirmation],
            description: "Items already placed in the user's Trash"
        ),
        CleanupRule(
            id: "largeold.file",
            category: .largeOldFiles,
            rootPolicy: .requestedRoots,
            defaultSafety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            description: "Large or old user file; never auto-selected as safe"
        ),
        CleanupRule(
            id: "duplicate.exact",
            category: .duplicates,
            rootPolicy: .requestedRoots,
            defaultSafety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            description: "Byte-identical duplicate confirmed by full hashing"
        ),
        CleanupRule(
            id: "image.similar",
            category: .similarImages,
            rootPolicy: .requestedRoots,
            defaultSafety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            description: "Visually similar image; never automatically deleted"
        ),
        CleanupRule(
            id: "mail.attachment.cache",
            category: .mailAttachments,
            rootPolicy: .userLibrary,
            defaultSafety: .review,
            deletionMode: .permanent,
            requirements: [.fullDiskAccess, .explicitConfirmation],
            description: "Locally cached mail attachment that can be downloaded again"
        ),
        CleanupRule(
            id: "timemachine.snapshot",
            category: .snapshots,
            rootPolicy: .userHome,
            defaultSafety: .review,
            deletionMode: .maintenance,
            requirements: [.privilegedHelper, .explicitConfirmation],
            description: "Time Machine local snapshot managed through the system tool, never by raw file deletion"
        )
    ]
}
