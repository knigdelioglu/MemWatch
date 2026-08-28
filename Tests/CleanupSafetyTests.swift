import Foundation

@main
struct CleanupSafetyTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("MemWatchCleanupSafety-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let requested = root.appendingPathComponent("requested", isDirectory: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: requested, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let context = CleanupScanContext(
            homeDirectory: home,
            requestedRoots: [requested],
            projectRoots: [requested],
            ignoredPaths: [],
            now: Date(),
            fullDiskAccessAvailable: false,
            privilegedHelperAvailable: false
        )
        let catalog = CleanupRuleCatalog()
        let engine = CleanupSafetyEngine()

        let cacheFile = caches.appendingPathComponent("com.example.cache")
        try Data("cache".utf8).write(to: cacheFile)
        let cacheCandidate = candidate(
            url: cacheFile,
            ruleID: "user.cache",
            category: .userCaches,
            safety: .safe,
            deletionMode: .permanent,
            requirements: [.applicationInactive]
        )
        let cacheAssessment = engine.assess(
            candidate: cacheCandidate,
            rule: requireRule("user.cache", catalog: catalog),
            context: context
        )
        precondition(cacheAssessment.canDelete, "Known user cache should pass filesystem safety policy")
        precondition(cacheAssessment.candidate.safety == .safe, "Known user cache should remain Safe")

        let realFile = requested.appendingPathComponent("real.txt")
        let symlink = requested.appendingPathComponent("link.txt")
        try Data("important".utf8).write(to: realFile)
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: realFile)
        let symlinkCandidate = candidate(
            url: symlink,
            ruleID: "largeold.file",
            category: .largeOldFiles,
            safety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation]
        )
        let symlinkAssessment = engine.assess(
            candidate: symlinkCandidate,
            rule: requireRule("largeold.file", catalog: catalog),
            context: context
        )
        precondition(!symlinkAssessment.canDelete, "Symlink target must be blocked")
        precondition(symlinkAssessment.candidate.safety == .protected, "Symlink target must become Protected")

        let permissiveContext = CleanupScanContext(
            homeDirectory: home,
            requestedRoots: [URL(fileURLWithPath: "/", isDirectory: true)],
            projectRoots: [requested],
            now: Date(),
            fullDiskAccessAvailable: true,
            privilegedHelperAvailable: true
        )
        let systemCandidate = CleanupCandidate(
            scannerID: "test",
            ruleID: "largeold.file",
            category: .largeOldFiles,
            url: URL(fileURLWithPath: "/System/Library", isDirectory: true),
            displayName: "System Library",
            logicalBytes: 0,
            allocatedBytes: 0,
            safety: .review,
            deletionMode: .trash,
            requirements: [.explicitConfirmation],
            reason: "test"
        )
        let systemAssessment = engine.assess(
            candidate: systemCandidate,
            rule: requireRule("largeold.file", catalog: catalog),
            context: permissiveContext
        )
        precondition(!systemAssessment.canDelete, "/System must remain blocked")

        let guardedFile = requested.appendingPathComponent("guarded.cache")
        try Data("guarded".utf8).write(to: guardedFile)
        let helperRule = CleanupRule(
            id: "test.helper",
            category: .systemCaches,
            rootPolicy: .requestedRoots,
            defaultSafety: .review,
            deletionMode: .privileged,
            requirements: [.privilegedHelper],
            description: "test"
        )
        let helperCandidate = candidate(
            url: guardedFile,
            ruleID: helperRule.id,
            category: .systemCaches,
            safety: .safe,
            deletionMode: .privileged
        )
        let helperAssessment = engine.assess(candidate: helperCandidate, rule: helperRule, context: context)
        precondition(helperAssessment.candidate.safety == .protected, "Missing privileged helper must protect the item")

        let fdaRule = CleanupRule(
            id: "test.fda",
            category: .mailAttachments,
            rootPolicy: .requestedRoots,
            defaultSafety: .review,
            deletionMode: .permanent,
            requirements: [.fullDiskAccess],
            description: "test"
        )
        let fdaCandidate = candidate(
            url: guardedFile,
            ruleID: fdaRule.id,
            category: .mailAttachments,
            safety: .review,
            deletionMode: .permanent
        )
        let fdaAssessment = engine.assess(candidate: fdaCandidate, rule: fdaRule, context: context)
        precondition(fdaAssessment.candidate.safety == .protected, "Missing Full Disk Access must protect the item")

        let ageRule = CleanupRule(
            id: "test.age",
            category: .logs,
            rootPolicy: .requestedRoots,
            defaultSafety: .safe,
            deletionMode: .permanent,
            minimumAge: 30 * 24 * 60 * 60,
            description: "test"
        )
        let recentCandidate = candidate(
            url: guardedFile,
            ruleID: ageRule.id,
            category: .logs,
            safety: .safe,
            deletionMode: .permanent,
            modifiedAt: Date()
        )
        let ageAssessment = engine.assess(candidate: recentCandidate, rule: ageRule, context: context)
        precondition(ageAssessment.candidate.safety == .review, "Recent age-gated item must be Review")
        precondition(ageAssessment.candidate.requirements.contains(.explicitConfirmation), "Recent item must require confirmation")

        let modelRoot = home.appendingPathComponent(".ollama/models", isDirectory: true)
        try fileManager.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        let modelFile = modelRoot.appendingPathComponent("model.gguf")
        try Data("model".utf8).write(to: modelFile)
        let modelCandidate = candidate(
            url: modelFile,
            ruleID: "ai.model",
            category: .aiArtifacts,
            safety: .safe,
            deletionMode: .permanent
        )
        let modelAssessment = engine.assess(
            candidate: modelCandidate,
            rule: requireRule("ai.model", catalog: catalog),
            context: context
        )
        precondition(modelAssessment.candidate.safety == .protected, "AI model weights must never enter automatic cleanup")
        precondition(modelAssessment.candidate.deletionMode == .none, "Protected model must have no deletion mode")

        let ignoredRoot = requested.appendingPathComponent("Keep", isDirectory: true)
        let ignoredContext = CleanupScanContext(
            homeDirectory: home,
            requestedRoots: [requested],
            projectRoots: [requested],
            ignoredPaths: [ignoredRoot.path],
            now: Date()
        )
        precondition(ignoredContext.isIgnored(ignoredRoot.appendingPathComponent("nested/file")), "Path ignore must cover descendants")

        print("PASS Cleanup safety policy")
    }

    private static func requireRule(_ id: CleanupRuleID, catalog: CleanupRuleCatalog) -> CleanupRule {
        guard let rule = catalog.rule(for: id) else {
            preconditionFailure("Missing rule \(id.rawValue)")
        }
        return rule
    }

    private static func candidate(
        url: URL,
        ruleID: CleanupRuleID,
        category: CleanupCategory,
        safety: CleanupSafetyLevel,
        deletionMode: CleanupDeletionMode,
        requirements: CleanupRequirements = [],
        modifiedAt: Date? = nil
    ) -> CleanupCandidate {
        CleanupCandidate(
            scannerID: "test",
            ruleID: ruleID,
            category: category,
            url: url.standardizedFileURL,
            displayName: url.lastPathComponent,
            logicalBytes: 1,
            allocatedBytes: 1,
            modifiedAt: modifiedAt,
            safety: safety,
            deletionMode: deletionMode,
            requirements: requirements,
            reason: "test",
            identity: CleanupPathValidator.identity(for: url)
        )
    }
}
