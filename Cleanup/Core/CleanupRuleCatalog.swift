import Foundation

enum CleanupRootPolicy: Equatable, Sendable {
    case userHome
    case userLibrary
    case temporaryDirectory
    case systemLibrary
    case privateVar
    case projectRoots
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

    init(id: CleanupRuleID, category: CleanupCategory, rootPolicy: CleanupRootPolicy, defaultSafety: CleanupSafetyLevel, deletionMode: CleanupDeletionMode, requirements: CleanupRequirements = [], minimumAge: TimeInterval? = nil, description: String) {
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

    func rule(for id: CleanupRuleID) -> CleanupRule? { rules[id] }
    var allRules: [CleanupRule] { Array(rules.values) }

    static let defaultRules: [CleanupRule] = [
        CleanupRule(id: "user.cache", category: .userCaches, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], description: "Regenerable user application cache"),
        CleanupRule(id: "user.log.old", category: .logs, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, minimumAge: 30 * 24 * 60 * 60, description: "Old user log file"),
        CleanupRule(id: "system.cache", category: .systemCaches, rootPolicy: .systemLibrary, defaultSafety: .review, deletionMode: .privileged, requirements: [.privilegedHelper], description: "System-wide cache approved by a typed privileged rule"),
        CleanupRule(id: "system.log.old", category: .logs, rootPolicy: .systemLibrary, defaultSafety: .review, deletionMode: .privileged, requirements: [.privilegedHelper], minimumAge: 30 * 24 * 60 * 60, description: "Old system-wide log"),
        CleanupRule(id: "privatevar.temp.old", category: .systemCaches, rootPolicy: .privateVar, defaultSafety: .review, deletionMode: .privileged, requirements: [.privilegedHelper], minimumAge: 7 * 24 * 60 * 60, description: "Old temporary data under an explicitly allowed private/var root"),

        CleanupRule(id: "xcode.deriveddata", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], description: "Xcode DerivedData that can be regenerated"),
        CleanupRule(id: "xcode.modulecache", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], description: "Xcode module cache that can be regenerated"),
        CleanupRule(id: "xcode.documentationcache", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], description: "Xcode documentation cache"),
        CleanupRule(id: "xcode.swiftpmcache", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], description: "Swift Package Manager cache used by Xcode"),
        CleanupRule(id: "xcode.previews", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, requirements: [.applicationInactive], description: "Generated Xcode preview artifacts"),
        CleanupRule(id: "xcode.devicesupport", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation, .applicationInactive], description: "Xcode device support files; removing them may require a later download"),
        CleanupRule(id: "xcode.simulatorcache", category: .xcode, rootPolicy: .userLibrary, defaultSafety: .review, deletionMode: .maintenance, requirements: [.explicitConfirmation, .applicationInactive], description: "Simulator cache or unavailable-runtime candidate; use a simulator-aware backend"),

        CleanupRule(id: "developer.cache", category: .developer, rootPolicy: .userHome, defaultSafety: .safe, deletionMode: .permanent, description: "Regenerable developer-tool cache"),
        CleanupRule(id: "developer.store", category: .developer, rootPolicy: .userHome, defaultSafety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], description: "Regenerable package/dependency store whose deletion can require a substantial re-download"),
        CleanupRule(id: "project.artifact", category: .projectArtifacts, rootPolicy: .projectRoots, defaultSafety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], description: "Regenerable project dependency or build artifact"),
        CleanupRule(id: "project.rust.target.verified", category: .projectArtifacts, rootPolicy: .projectRoots, defaultSafety: .safe, deletionMode: .permanent, requirements: [.explicitConfirmation, .buildInactive], description: "Cargo-verified regenerable Rust build artifacts"),

        CleanupRule(id: "ai.cache", category: .aiArtifacts, rootPolicy: .userHome, defaultSafety: .safe, deletionMode: .permanent, description: "AI tool cache that is not a model weight or user data"),
        CleanupRule(id: "ai.temp", category: .aiArtifacts, rootPolicy: .userHome, defaultSafety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], description: "Incomplete or temporary AI-tool download/generation data"),
        CleanupRule(id: "ai.model", category: .aiArtifacts, rootPolicy: .userHome, defaultSafety: .protected, deletionMode: .none, description: "Downloaded local model; visible for management but excluded from automatic cleanup"),

        CleanupRule(id: "application.leftover.user", category: .applicationLeftovers, rootPolicy: .userLibrary, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "High-confidence user leftover belonging to an uninstalled application"),
        CleanupRule(id: "application.leftover.system", category: .applicationLeftovers, rootPolicy: .systemLibrary, defaultSafety: .review, deletionMode: .privileged, requirements: [.privilegedHelper, .explicitConfirmation], description: "High-confidence system-wide leftover belonging to an uninstalled application"),
        CleanupRule(id: "launchitem.orphan.user", category: .launchItems, rootPolicy: .userLibrary, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "User LaunchAgent whose configured executable is absent"),
        CleanupRule(id: "launchitem.orphan.system", category: .launchItems, rootPolicy: .systemLibrary, defaultSafety: .review, deletionMode: .privileged, requirements: [.privilegedHelper, .explicitConfirmation], description: "System LaunchAgent/LaunchDaemon whose configured executable is absent"),
        CleanupRule(id: "diagnostic.user.old", category: .logs, rootPolicy: .userLibrary, defaultSafety: .safe, deletionMode: .permanent, minimumAge: 30 * 24 * 60 * 60, description: "Old user crash/hang diagnostic report"),
        CleanupRule(id: "diagnostic.system.old", category: .logs, rootPolicy: .systemLibrary, defaultSafety: .review, deletionMode: .privileged, requirements: [.privilegedHelper], minimumAge: 30 * 24 * 60 * 60, description: "Old system crash/hang diagnostic report"),

        CleanupRule(id: "ios.backup", category: .iosBackups, rootPolicy: .userLibrary, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "Local Apple-device backup"),
        CleanupRule(id: "downloads.review", category: .downloads, rootPolicy: .userHome, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "Download, installer, archive or partial download selected for user review"),
        CleanupRule(id: "trash.user", category: .trash, rootPolicy: .userHome, defaultSafety: .review, deletionMode: .permanent, requirements: [.explicitConfirmation], description: "Items already placed in the user's Trash"),
        CleanupRule(id: "largeold.file", category: .largeOldFiles, rootPolicy: .requestedRoots, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "Large or old user file; never auto-selected as safe"),
        CleanupRule(id: "duplicate.exact", category: .duplicates, rootPolicy: .requestedRoots, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "Byte-identical duplicate confirmed by full hashing"),
        CleanupRule(id: "image.similar", category: .similarImages, rootPolicy: .requestedRoots, defaultSafety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], description: "Visually similar image; never automatically deleted"),
        CleanupRule(id: "mail.attachment.cache", category: .mailAttachments, rootPolicy: .userLibrary, defaultSafety: .review, deletionMode: .permanent, requirements: [.fullDiskAccess, .explicitConfirmation, .applicationInactive], description: "Locally cached Mail attachment that can be downloaded again"),
        CleanupRule(id: "timemachine.snapshot", category: .snapshots, rootPolicy: .userHome, defaultSafety: .review, deletionMode: .maintenance, requirements: [.privilegedHelper, .explicitConfirmation], description: "Time Machine local snapshot managed through the system tool, never by raw file deletion")
    ]
}
