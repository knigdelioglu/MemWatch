import CoreGraphics
import Foundation
import ImageIO

@main
struct CleanupScannerFixtureTests {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MemWatchScannerFixtures-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let context = CleanupScanContext(
            homeDirectory: home,
            requestedRoots: [documents],
            projectRoots: [projects],
            now: Date(),
            fullDiskAccessAvailable: true,
            privilegedHelperAvailable: false
        )

        let cache = home.appendingPathComponent("Library/Caches/org.example.fixture", isDirectory: true)
        try writePayload(into: cache, fm: fm)
        assertContains(try await UserCacheScanner().scan(context: context), path: cache.path, label: "user cache")

        let log = home.appendingPathComponent("Library/Logs/fixture.log")
        try writeFile(log, bytes: 4096, fm: fm)
        assertContains(try await UserLogScanner().scan(context: context), path: log.path, label: "user log")

        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/FixtureProject", isDirectory: true)
        try writePayload(into: derived, fm: fm)
        assertContains(try await XcodeCleanupScanner().scan(context: context), path: derived.path, label: "Xcode DerivedData")

        let npmCache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try writePayload(into: npmCache, fm: fm)
        assertContains(try await DeveloperCacheScanner().scan(context: context), path: npmCache.path, label: "developer cache")

        let nodeModules = projects.appendingPathComponent("FixtureApp/node_modules", isDirectory: true)
        try writePayload(into: nodeModules, fm: fm)
        assertContains(try await ProjectArtifactScanner().scan(context: context), path: nodeModules.path, label: "project artifact")

        let ollama = home.appendingPathComponent(".ollama/models", isDirectory: true)
        try writePayload(into: ollama, fm: fm)
        let aiItems = try await AIArtifactScanner().scan(context: context)
        assertContains(aiItems, path: ollama.path, label: "AI model")
        precondition(aiItems.first(where: { $0.url.path == ollama.path })?.safety == .protected, "AI models must stay Protected")

        let installer = home.appendingPathComponent("Downloads/fixture.dmg")
        try writeFile(installer, bytes: 4096, fm: fm)
        assertContains(try await DownloadsScanner().scan(context: context), path: installer.path, label: "download")

        let trashItem = home.appendingPathComponent(".Trash/fixture.txt")
        try writeFile(trashItem, bytes: 4096, fm: fm)
        assertContains(try await TrashScanner().scan(context: context), path: trashItem.path, label: "Trash")

        let backup = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/fixture-udid", isDirectory: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let backupInfo: [String: Any] = [
            "Device Name": "Fixture iPhone",
            "Product Version": "27.0",
            "Last Backup Date": Date(timeIntervalSince1970: 1_700_000_000)
        ]
        let backupData = try PropertyListSerialization.data(fromPropertyList: backupInfo, format: .xml, options: 0)
        try backupData.write(to: backup.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x12, count: 4096).write(to: backup.appendingPathComponent("Manifest.db"))
        assertContains(try await IOSBackupScanner().scan(context: context), path: backup.path, label: "iOS backup")

        let orphanPreference = home.appendingPathComponent("Library/Preferences/org.example.memwatchfixtureorphan.plist")
        try writeFile(orphanPreference, bytes: 4096, fm: fm)
        assertContains(try await ApplicationLeftoverScanner().scan(context: context), path: orphanPreference.path, label: "application leftover")

        let launchAgent = home.appendingPathComponent("Library/LaunchAgents/org.example.memwatchfixture.plist")
        try fm.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let launchPlist: [String: Any] = [
            "Label": "org.example.memwatchfixture",
            "Program": "/definitely/missing/memwatch-fixture"
        ]
        let launchData = try PropertyListSerialization.data(fromPropertyList: launchPlist, format: .xml, options: 0)
        try launchData.write(to: launchAgent)
        assertContains(try await LaunchItemScanner().scan(context: context), path: launchAgent.path, label: "orphan launch agent")

        let diagnostic = home.appendingPathComponent("Library/Logs/DiagnosticReports/fixture.crash")
        try writeFile(diagnostic, bytes: 4096, fm: fm)
        assertContains(try await DiagnosticReportScanner().scan(context: context), path: diagnostic.path, label: "diagnostic report")

        let oldLarge = documents.appendingPathComponent("old-large.bin")
        try createSparseFile(oldLarge, logicalBytes: 110 * 1_024 * 1_024, fm: fm)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -200 * 24 * 60 * 60)], ofItemAtPath: oldLarge.path)
        assertContains(try await LargeOldFileScanner().scan(context: context), path: oldLarge.path, label: "large/old file")

        let duplicateA = documents.appendingPathComponent("duplicate-a.bin")
        let duplicateB = documents.appendingPathComponent("duplicate-b.bin")
        let duplicatePayload = Data(repeating: 0x44, count: 1_100_000)
        try duplicatePayload.write(to: duplicateA)
        try duplicatePayload.write(to: duplicateB)
        let duplicates = try await ExactDuplicateScanner().scan(context: context)
        precondition(
            duplicates.contains(where: { $0.url.path == duplicateA.path || $0.url.path == duplicateB.path }),
            "Exact duplicate scanner must return one of the byte-identical fixture copies"
        )

        let imageA = documents.appendingPathComponent("similar-a.png")
        let imageB = documents.appendingPathComponent("similar-b.png")
        try writeFixtureImage(to: imageA)
        try writeFixtureImage(to: imageB)
        let similar = try await SimilarImageScanner().scan(context: context)
        precondition(
            similar.contains(where: { $0.url.path == imageA.path || $0.url.path == imageB.path }),
            "Similar-image scanner must classify one of two identical rendered images for review"
        )
        precondition(similar.allSatisfy { $0.safety == .review && $0.deletionMode == .trash })

        let attachment = home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/fixture/attachment.pdf")
        try writeFile(attachment, bytes: 4096, fm: fm)
        assertContains(try await MailAttachmentScanner().scan(context: context), path: attachment.deletingLastPathComponent().path, label: "Mail attachment cache")

        print("PASS Deep cleanup scanner fixtures")
    }

    private static func assertContains(_ items: [CleanupCandidate], path: String, label: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        precondition(items.contains(where: { $0.url.standardizedFileURL.path == standardized }), "Missing \(label) fixture: \(standardized)")
    }

    private static func writePayload(into directory: URL, fm: FileManager) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: 4096).write(to: directory.appendingPathComponent("payload.bin"))
    }

    private static func writeFile(_ url: URL, bytes: Int, fm: FileManager) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: bytes).write(to: url)
    }

    private static func createSparseFile(_ url: URL, logicalBytes: UInt64, fm: FileManager) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        precondition(fm.createFile(atPath: url.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: logicalBytes)
        try handle.close()
    }

    private static func writeFixtureImage(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 96,
            height: 96,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Could not create image fixture context")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 18, y: 18, width: 60, height: 60))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            preconditionFailure("Could not create PNG fixture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination), "Could not write PNG fixture")
    }
}
