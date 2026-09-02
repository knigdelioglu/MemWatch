import Foundation

struct CleanupScanPolicy: Sendable {
    init() {}
    func skips(scanner: any CleanupScanner) -> Bool { false }
    func skips(candidate: CleanupCandidate) -> Bool { false }
}

struct PrivilegedSystemScanner: CleanupScanner {
    let id: CleanupScannerID = "fixture-privileged"
    let category: CleanupCategory = .systemCaches

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] { [] }
}

private struct FixtureScanner: CleanupScanner {
    let id: CleanupScannerID
    let candidates: [CleanupCandidate]
    let category: CleanupCategory = .projectArtifacts

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        candidates
    }
}

@main
struct CleanupScanEngineTests {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MemWatchScanEngine-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let projectRoot = home.appendingPathComponent("Projects/fixture", isDirectory: true)
        let duplicatePath = projectRoot.appendingPathComponent(".build", isDirectory: true)
        let nestedPath = duplicatePath.appendingPathComponent("node_modules", isDirectory: true)
        try fileManager.createDirectory(at: nestedPath, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4096).write(to: duplicatePath.appendingPathComponent("payload"))
        try Data(repeating: 0x24, count: 1024).write(to: nestedPath.appendingPathComponent("payload"))
        defer { try? fileManager.removeItem(at: root) }

        let context = CleanupScanContext(homeDirectory: home, projectRoots: [projectRoot])
        let first = makeCandidate(
            scannerID: "fixture-one",
            url: duplicatePath,
            logicalBytes: 4096,
            allocatedBytes: 4096
        )
        let samePath = makeCandidate(
            scannerID: "fixture-two",
            url: duplicatePath,
            logicalBytes: 4096,
            allocatedBytes: 4096,
            safety: .review,
            requirements: [.explicitConfirmation]
        )
        let nested = makeCandidate(
            scannerID: "fixture-two",
            url: nestedPath,
            logicalBytes: 1024,
            allocatedBytes: 1024
        )
        let sameNestedPath = makeCandidate(
            scannerID: "fixture-one",
            url: nestedPath,
            logicalBytes: 1024,
            allocatedBytes: 1024,
            safety: .review,
            requirements: [.explicitConfirmation]
        )

        let engine = CleanupScanEngine(
            scanners: [
                FixtureScanner(id: "fixture-one", candidates: [first, sameNestedPath]),
                FixtureScanner(id: "fixture-two", candidates: [samePath, nested])
            ],
            safetyEngine: CleanupSafetyEngine(
                activityGuard: CleanupActivityGuard { _ in .inactive }
            )
        )
        let result = try await engine.scan(context: context)

        precondition(result.items.count == 1, "Overlapping parent/child targets must not both remain actionable")
        guard let retained = result.items.first else {
            preconditionFailure("The more-specific cleanup target should remain")
        }
        precondition(retained.url.standardizedFileURL.path == nestedPath.standardizedFileURL.path)
        precondition(retained.safety == .review, "Coalescing must preserve the most restrictive safety level")
        precondition(retained.requirements.contains(.explicitConfirmation), "Coalescing must preserve confirmation requirements")
        precondition(result.issues.count >= 2, "Duplicate and overlapping targets must be reported as scan issues")

        print("PASS Cleanup scan coalescing and overlap policy")
    }

    private static func makeCandidate(
        scannerID: CleanupScannerID,
        url: URL,
        logicalBytes: UInt64,
        allocatedBytes: UInt64,
        safety: CleanupSafetyLevel = .safe,
        requirements: CleanupRequirements = []
    ) -> CleanupCandidate {
        CleanupCandidate(
            scannerID: scannerID,
            ruleID: "project.artifact",
            category: .projectArtifacts,
            url: url.standardizedFileURL,
            displayName: url.lastPathComponent,
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            safety: safety,
            deletionMode: .permanent,
            requirements: requirements,
            reason: "fixture",
            identity: CleanupPathValidator.identity(for: url)
        )
    }
}
