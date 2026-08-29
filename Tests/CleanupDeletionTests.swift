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

        let dryTarget = projects.appendingPathComponent("dry-project/.build", isDirectory: true)
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

        let activeCache = home.appendingPathComponent("Library/Caches/org.example.active", isDirectory: true)
        try fm.createDirectory(at: activeCache, withIntermediateDirectories: true)
        try Data("active".utf8).write(to: activeCache.appendingPathComponent("payload"))
        let activeCacheCandidate = CleanupCandidate(
            scannerID: "user-cache",
            ruleID: "user.cache",
            category: .userCaches,
            url: activeCache,
            displayName: "Active app cache",
            logicalBytes: 6,
            allocatedBytes: 6,
            safety: .safe,
            deletionMode: .permanent,
            requirements: [.applicationInactive],
            reason: "test active app cache",
            identity: CleanupPathValidator.identity(for: activeCache)
        )
        let activeAppEngine = CleanupDeletionEngine(
            activityGuard: CleanupActivityGuard { _ in .active("Fixture App") }
        )
        let activeAppReport = await activeAppEngine.execute(
            candidates: [activeCacheCandidate],
            context: context,
            mode: .apply
        )
        precondition(activeAppReport.results[0].status == .failed, "A cache for a running app must not be removed")
        precondition(activeAppReport.results[0].message.contains("still running"), "Active app failure must explain the blocking condition")
        precondition(fm.fileExists(atPath: activeCache.path), "Active app cache must survive the blocked cleanup")

        let unknownAppEngine = CleanupDeletionEngine(
            activityGuard: CleanupActivityGuard { _ in .unknown("Unknown App") }
        )
        let unknownAppReport = await unknownAppEngine.execute(
            candidates: [activeCacheCandidate],
            context: context,
            mode: .apply,
            explicitlyConfirmedIDs: [activeCacheCandidate.id]
        )
        precondition(unknownAppReport.results[0].status == .failed, "Unknown application state must remain blocked even after confirmation")
        precondition(unknownAppReport.results[0].message.contains("could not safely verify"), "Unknown application failure must explain the safety block")
        precondition(fm.fileExists(atPath: activeCache.path), "Unknown application state must preserve the cache")

        let applyTarget = projects.appendingPathComponent("apply-project/.build", isDirectory: true)
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

        let raceTarget = projects.appendingPathComponent("race-project/.build", isDirectory: true)
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

        let inPlaceTarget = projects.appendingPathComponent("in-place-project/.build", isDirectory: false)
        try fm.createDirectory(at: inPlaceTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("before".utf8).write(to: inPlaceTarget)
        let staleContentCandidate = projectCandidate(inPlaceTarget)
        try Data(repeating: 0x7F, count: 4096).write(to: inPlaceTarget)
        let inPlaceReport = await engine.execute(
            candidates: [staleContentCandidate],
            context: context,
            mode: .apply,
            explicitlyConfirmedIDs: [staleContentCandidate.id]
        )
        precondition(inPlaceReport.results[0].status == .failed, "In-place target mutation must block deletion")
        precondition(fm.fileExists(atPath: inPlaceTarget.path), "Mutated target must survive stale-candidate deletion")

        let nestedSymlinkTarget = projects.appendingPathComponent("nested-symlink-project/.build", isDirectory: true)
        let protectedOutside = root.appendingPathComponent("protected-outside.txt")
        try fm.createDirectory(at: nestedSymlinkTarget, withIntermediateDirectories: true)
        try Data("must survive".utf8).write(to: protectedOutside)
        try fm.createSymbolicLink(
            at: nestedSymlinkTarget.appendingPathComponent("link"),
            withDestinationURL: protectedOutside
        )
        let nestedSymlinkCandidate = projectCandidate(nestedSymlinkTarget)
        let nestedSymlinkReport = await engine.execute(
            candidates: [nestedSymlinkCandidate],
            context: context,
            mode: .apply,
            explicitlyConfirmedIDs: [nestedSymlinkCandidate.id]
        )
        precondition(nestedSymlinkReport.results[0].status == .failed, "Nested symlink must block recursive deletion")
        precondition(fm.fileExists(atPath: nestedSymlinkTarget.path), "Target containing a nested symlink must survive")
        precondition(fm.fileExists(atPath: protectedOutside.path), "A nested symlink target must never be touched")

        let trashTarget = home.appendingPathComponent("Downloads/trash-target.zip", isDirectory: false)
        try fm.createDirectory(at: trashTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("trash fixture".utf8).write(to: trashTarget)
        guard let trashIdentity = CleanupSecureFileOperations.identity(atPath: trashTarget.path) else {
            preconditionFailure("Trash fixture identity should be readable")
        }
        try CleanupSecureFileOperations.moveToTrash(
            atPath: trashTarget.path,
            expectedIdentity: trashIdentity,
            trashDirectoryPath: home.appendingPathComponent(".Trash", isDirectory: true).path
        )
        precondition(!fm.fileExists(atPath: trashTarget.path), "Secure Trash move must remove the original path")
        let trashEntries = try fm.contentsOfDirectory(at: home.appendingPathComponent(".Trash", isDirectory: true), includingPropertiesForKeys: nil)
        precondition(trashEntries.contains { $0.lastPathComponent.hasPrefix("trash-target.zip.memwatch-") }, "Secure Trash move must create a unique destination")

        let cancelledTarget = projects.appendingPathComponent("cancelled-project/.build", isDirectory: true)
        try fm.createDirectory(at: cancelledTarget, withIntermediateDirectories: true)
        try Data("cancel me".utf8).write(to: cancelledTarget.appendingPathComponent("payload"))
        let cancelledCandidate = projectCandidate(cancelledTarget)
        let cancelledTask = Task {
            await engine.execute(
                candidates: [cancelledCandidate],
                context: context,
                mode: .apply,
                explicitlyConfirmedIDs: [cancelledCandidate.id]
            )
        }
        cancelledTask.cancel()
        let cancelledReport = await cancelledTask.value
        precondition(cancelledReport.outcome == .cancelled, "Cancelled cleanup must report a cancelled outcome")
        precondition(cancelledReport.reclaimVerification == .cancelled, "Cancelled cleanup must not claim reclaim verification")
        precondition(fm.fileExists(atPath: cancelledTarget.path), "Cancellation before execution must preserve the target")

        let confirmTarget = projects.appendingPathComponent("confirmation-project/.build", isDirectory: true)
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

        let simulatorCache = home.appendingPathComponent("Library/Developer/CoreSimulator/Caches/TestCache", isDirectory: true)
        try fm.createDirectory(at: simulatorCache, withIntermediateDirectories: true)
        try Data("simulator".utf8).write(to: simulatorCache.appendingPathComponent("cache.bin"))
        let maintenanceCandidate = xcodeMaintenanceCandidate(simulatorCache)
        let maintenanceBackend = CleanupMaintenanceBackend(commandRunner: { _ in
            "{\"devices\": {}}"
        })
        _ = try maintenanceBackend.execute(maintenanceCandidate, context: context)
        precondition(!fm.fileExists(atPath: simulatorCache.path), "Approved simulator cache must be executable by maintenance backend")

        let rejected = home.appendingPathComponent("Library/Developer/DoNotDelete", isDirectory: true)
        try fm.createDirectory(at: rejected, withIntermediateDirectories: true)
        let rejectedCandidate = xcodeMaintenanceCandidate(rejected)
        do {
            _ = try maintenanceBackend.execute(rejectedCandidate, context: context)
            preconditionFailure("Maintenance backend must reject paths outside its Xcode allowlist")
        } catch CleanupDeletionError.maintenanceTargetRejected {
            precondition(fm.fileExists(atPath: rejected.path), "Rejected maintenance target must survive")
        }

        print("PASS Cleanup deletion, TOCTOU and maintenance allowlist")
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

    private static func xcodeMaintenanceCandidate(_ url: URL) -> CleanupCandidate {
        let size = CleanupFileSizer().measure(url)
        return CleanupCandidate(
            scannerID: "xcode-cleanup",
            ruleID: "xcode.simulatorcache",
            category: .xcode,
            url: url.standardizedFileURL,
            displayName: url.lastPathComponent,
            logicalBytes: size.logicalBytes,
            allocatedBytes: size.allocatedBytes,
            safety: .review,
            deletionMode: .maintenance,
            requirements: [.explicitConfirmation, .applicationInactive],
            reason: "test Xcode maintenance target",
            identity: CleanupPathValidator.identity(for: url)
        )
    }
}
