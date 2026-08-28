import AppKit
import Foundation

struct PrivilegedHelperClient: Sendable {
    init() {}

    func execute(_ request: PrivilegedOperationRequest) async throws -> PrivilegedOperationResponse {
        throw NSError(domain: "CleanupDeletionTests", code: 999, userInfo: [NSLocalizedDescriptionKey: "Privileged path unexpectedly reached by fixture test"])
    }
}

@main
struct CleanupDeletionTests {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MemWatchCleanupDeletion-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let context = CleanupScanContext(
            homeDirectory: home,
            requestedRoots: [projects],
            projectRoots: [projects],
            now: Date(),
            fullDiskAccessAvailable: false,
            privilegedHelperAvailable: false
        )
        let engine = CleanupDeletionEngine()

        let dryTarget = projects.appendingPathComponent("dry-target", isDirectory: true)
        try fm.createDirectory(at: dryTarget, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: dryTarget.appendingPathComponent("payload"))
        let dryCandidate = projectCandidate(dryTarget)
        let dryReport = await engine.execute(
            candidates: [dryCandidate],
            context: context,
            mode: .dryRun,
            explicitlyConfirmedIDs: [dryCandidate.id]
        )
        precondition(dryReport.results.count == 1)
        precondition(dryReport.results[0].status == .wouldRemove, "Dry run should report wouldRemove")
        precondition(fm.fileExists(atPath: dryTarget.path), "Dry run must not mutate the filesystem")

        let applyTarget = projects.appendingPathComponent("target", isDirectory: true)
        try fm.createDirectory(at: applyTarget, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4096).write(to: applyTarget.appendingPathComponent("artifact.bin"))
        let applyCandidate = projectCandidate(applyTarget)
        let applyReport = await engine.execute(
            candidates: [applyCandidate],
            context: context,
            mode: .apply,
            explicitlyConfirmedIDs: [applyCandidate.id]
        )
        precondition(applyReport.results[0].status == .removed, "Confirmed project artifact should be removed")
        precondition(!fm.fileExists(atPath: applyTarget.path), "Applied deletion must remove the original path")

        let raceTarget = projects.appendingPathComponent("race-target", isDirectory: true)
        try fm.createDirectory(at: raceTarget, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: raceTarget.appendingPathComponent("payload"))
        let staleCandidate = projectCandidate(raceTarget)
        try fm.removeItem(at: raceTarget)
        try fm.createDirectory(at: raceTarget, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: raceTarget.appendingPathComponent("payload"))
        let raceReport = await engine.execute(
            candidates: [staleCandidate],
            context: context,
            mode: .apply,
            explicitlyConfirmedIDs: [staleCandidate.id]
        )
        precondition(raceReport.results[0].status == .failed, "Changed inode must block deletion")
        precondition(raceReport.results[0].message.contains("changed after scanning"), "Failure should explain stale identity")
        precondition(fm.fileExists(atPath: raceTarget.path), "Replacement object must survive stale-candidate deletion")

        let confirmTarget = projects.appendingPathComponent("confirmation-target", isDirectory: true)
        try fm.createDirectory(at: confirmTarget, withIntermediateDirectories: true)
        let confirmCandidate = projectCandidate(confirmTarget)
        let confirmationReport = await engine.execute(
            candidates: [confirmCandidate],
            context: context,
            mode: .apply,
            explicitlyConfirmedIDs: []
        )
        precondition(confirmationReport.results[0].status == .failed, "Review item must require explicit confirmation")
        precondition(fm.fileExists(atPath: confirmTarget.path), "Unconfirmed item must not be deleted")

        print("PASS Cleanup deletion and TOCTOU")
    }

    private static func projectCandidate(_ url: URL) -> CleanupCandidate {
        let size = CleanupFileSizer().measure(url)
        return CleanupCandidate(
            scannerID: "project-artifact",
            ruleID: "project.artifact",
            category: .projectArtifacts,
            url: url.standardizedFileURL,
            displayName: url.lastPathComponent,
            logicalBytes: size.logicalBytes,
            allocatedBytes: size.allocatedBytes,
            modifiedAt: Date(timeIntervalSinceNow: -40 * 24 * 60 * 60),
            safety: .review,
            deletionMode: .permanent,
            requirements: [.explicitConfirmation],
            reason: "test project artifact",
            identity: CleanupPathValidator.identity(for: url)
        )
    }
}
