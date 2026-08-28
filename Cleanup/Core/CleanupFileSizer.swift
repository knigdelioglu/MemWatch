import CryptoKit
import Darwin
import Foundation
import ImageIO
import Vision

struct CleanupFileSize: Equatable, Sendable {
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
}

struct CleanupFileSizer: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func measure(_ url: URL) -> CleanupFileSize {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let rootValues = try? url.resourceValues(forKeys: keys) else { return CleanupFileSize(logicalBytes: 0, allocatedBytes: 0) }
        if rootValues.isSymbolicLink == true { return CleanupFileSize(logicalBytes: 0, allocatedBytes: 0) }
        if rootValues.isDirectory != true {
            let measured = size(from: rootValues)
            if let metadata = hardlinkMetadata(for: url), metadata.linkCount > 1 {
                return CleanupFileSize(logicalBytes: measured.logicalBytes, allocatedBytes: 0)
            }
            return measured
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else {
            return CleanupFileSize(logicalBytes: 0, allocatedBytes: 0)
        }

        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        var hardlinks: [HardlinkKey: HardlinkAggregate] = [:]

        while let childURL = enumerator.nextObject() as? URL {
            guard let values = try? childURL.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let childSize = size(from: values)

            if let metadata = hardlinkMetadata(for: childURL), metadata.linkCount > 1 {
                var aggregate = hardlinks[metadata.key] ?? HardlinkAggregate(
                    logicalBytes: childSize.logicalBytes,
                    allocatedBytes: childSize.allocatedBytes,
                    observedLinks: 0,
                    totalLinks: metadata.linkCount
                )
                aggregate.observedLinks += 1
                aggregate.totalLinks = max(aggregate.totalLinks, metadata.linkCount)
                hardlinks[metadata.key] = aggregate
                continue
            }

            logical = addingWithoutOverflow(logical, childSize.logicalBytes)
            allocated = addingWithoutOverflow(allocated, childSize.allocatedBytes)
        }

        for aggregate in hardlinks.values {
            logical = addingWithoutOverflow(logical, aggregate.logicalBytes)
            if aggregate.observedLinks >= aggregate.totalLinks {
                allocated = addingWithoutOverflow(allocated, aggregate.allocatedBytes)
            }
        }

        return CleanupFileSize(logicalBytes: logical, allocatedBytes: allocated)
    }

    private struct HardlinkKey: Hashable {
        let deviceID: UInt64
        let inode: UInt64
    }

    private struct HardlinkAggregate {
        let logicalBytes: UInt64
        let allocatedBytes: UInt64
        var observedLinks: UInt64
        var totalLinks: UInt64
    }

    private func hardlinkMetadata(for url: URL) -> (key: HardlinkKey, linkCount: UInt64)? {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (UInt32(info.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFREG) else {
            return nil
        }
        return (
            HardlinkKey(deviceID: UInt64(info.st_dev), inode: UInt64(info.st_ino)),
            UInt64(info.st_nlink)
        )
    }

    private func size(from values: URLResourceValues) -> CleanupFileSize {
        let logical = positiveUInt64(values.fileSize)
        let allocated = positiveUInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize)
        return CleanupFileSize(logicalBytes: logical, allocatedBytes: allocated > 0 ? allocated : logical)
    }

    private func positiveUInt64(_ value: Int?) -> UInt64 {
        guard let value, value > 0 else { return 0 }
        return UInt64(value)
    }

    private func addingWithoutOverflow(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : value
    }
}

// MARK: - Installed application attribution

private struct InstalledApplicationIndex {
    let bundleIdentifiers: Set<String>

    static func build(homeDirectory: URL) -> InstalledApplicationIndex {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        var identifiers = Set<String>()
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                collectBundleIDs(from: url, into: &identifiers)
                enumerator.skipDescendants()
            }
        }
        return InstalledApplicationIndex(bundleIdentifiers: identifiers)
    }

    func isRelatedToInstalledApplication(_ identifier: String) -> Bool {
        if bundleIdentifiers.contains(identifier) { return true }
        return bundleIdentifiers.contains { installed in
            identifier.hasPrefix(installed + ".") || installed.hasPrefix(identifier + ".")
        }
    }

    private static func collectBundleIDs(from appURL: URL, into identifiers: inout Set<String>) {
        if let identifier = Bundle(url: appURL)?.bundleIdentifier { identifiers.insert(identifier) }
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: contents, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return }
        let bundleExtensions: Set<String> = ["app", "appex", "xpc"]
        for case let url as URL in enumerator where bundleExtensions.contains(url.pathExtension.lowercased()) {
            if let identifier = Bundle(url: url)?.bundleIdentifier { identifiers.insert(identifier) }
            enumerator.skipDescendants()
        }
    }
}

// MARK: - Application leftovers

struct ApplicationLeftoverScanner: CleanupScanner {
    let id: CleanupScannerID = "application-leftover"
    let category: CleanupCategory = .applicationLeftovers
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let index = InstalledApplicationIndex.build(homeDirectory: context.homeDirectory)
        let library = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        var results: [CleanupCandidate] = []

        let userRoots = ["Preferences", "Containers", "HTTPStorages", "WebKit", "Saved Application State"].map {
            library.appendingPathComponent($0, isDirectory: true)
        }
        for root in userRoots {
            try Task.checkCancellation()
            for url in support.immediateChildren(of: root) {
                try Task.checkCancellation()
                guard !context.isIgnored(url), let identifier = identifierCandidate(for: url), isHighConfidenceOrphan(identifier, index: index) else { continue }
                if let item = support.candidate(url: url, scannerID: id, ruleID: "application.leftover.user", category: category, displayName: "Orphan: \(identifier)", safety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], reason: "Exact bundle-style identifier is not related to any installed application", regenerationHint: "Review before removal; application leftovers are never auto-selected as safe."), item.allocatedBytes > 0 {
                    results.append(item)
                }
            }
        }

        let systemRoots = [
            URL(fileURLWithPath: "/Library/Preferences", isDirectory: true),
            URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
        ]
        for root in systemRoots where FileManager.default.fileExists(atPath: root.path) {
            try Task.checkCancellation()
            for url in support.immediateChildren(of: root) {
                try Task.checkCancellation()
                guard let identifier = identifierCandidate(for: url), isHighConfidenceOrphan(identifier, index: index) else { continue }
                if let item = support.candidate(url: url, scannerID: id, ruleID: "application.leftover.system", category: category, displayName: "System orphan: \(identifier)", safety: .review, deletionMode: .privileged, requirements: [.privilegedHelper, .explicitConfirmation], reason: "Exact bundle-style identifier is not related to any installed application", regenerationHint: "A privileged review is required before removal."), item.allocatedBytes > 0 {
                    results.append(item)
                }
            }
        }

        return deduplicated(results)
    }

    private func identifierCandidate(for url: URL) -> String? {
        var value = url.lastPathComponent
        for suffix in [".savedState", ".plist"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        guard looksLikeBundleIdentifier(value) else { return nil }
        return value
    }

    private func looksLikeBundleIdentifier(_ value: String) -> Bool {
        guard value.count >= 5, value.contains("."), !value.hasPrefix("com.apple."), !value.hasPrefix("group.com.apple.") else { return false }
        let components = value.split(separator: ".")
        return components.count >= 2 && components.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    private func isHighConfidenceOrphan(_ identifier: String, index: InstalledApplicationIndex) -> Bool {
        !index.isRelatedToInstalledApplication(identifier)
    }

    private func deduplicated(_ items: [CleanupCandidate]) -> [CleanupCandidate] {
        var paths = Set<String>()
        return items.filter { paths.insert($0.url.path).inserted }
    }
}

// MARK: - Orphan launch items

struct LaunchItemScanner: CleanupScanner {
    let id: CleanupScannerID = "launch-item"
    let category: CleanupCategory = .launchItems
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let userLibrary = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let roots: [(URL, CleanupRuleID, CleanupDeletionMode, CleanupRequirements)] = [
            (userLibrary.appendingPathComponent("LaunchAgents", isDirectory: true), "launchitem.orphan.user", .trash, [.explicitConfirmation]),
            (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), "launchitem.orphan.system", .privileged, [.privilegedHelper, .explicitConfirmation]),
            (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), "launchitem.orphan.system", .privileged, [.privilegedHelper, .explicitConfirmation])
        ]
        var results: [CleanupCandidate] = []
        for (root, ruleID, mode, requirements) in roots where FileManager.default.fileExists(atPath: root.path) {
            try Task.checkCancellation()
            for plistURL in support.immediateChildren(of: root) where plistURL.pathExtension.lowercased() == "plist" {
                try Task.checkCancellation()
                guard let data = try? Data(contentsOf: plistURL), let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil), let plist = object as? [String: Any] else { continue }
                let label = (plist["Label"] as? String) ?? plistURL.deletingPathExtension().lastPathComponent
                guard !label.hasPrefix("com.apple.") else { continue }
                let configuredProgram = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                guard let configuredProgram, configuredProgram.hasPrefix("/") else { continue }
                guard !FileManager.default.fileExists(atPath: configuredProgram) else { continue }
                if let item = support.candidate(url: plistURL, scannerID: id, ruleID: ruleID, category: category, displayName: label, safety: .review, deletionMode: mode, requirements: requirements, reason: "Launch item points to missing executable: \(configuredProgram)", regenerationHint: "The launch item is only considered orphaned because its configured executable is absent.") {
                    results.append(item)
                }
            }
        }
        return results
    }
}

// MARK: - Diagnostic reports

struct DiagnosticReportScanner: CleanupScanner {
    let id: CleanupScannerID = "diagnostic-report"
    let category: CleanupCategory = .logs
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let userRoot = context.homeDirectory.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let systemRoot = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true)
        var results: [CleanupCandidate] = []
        for url in support.immediateChildren(of: userRoot) {
            try Task.checkCancellation()
            if let item = support.candidate(url: url, scannerID: id, ruleID: "diagnostic.user.old", category: category, safety: .safe, deletionMode: .permanent, reason: "Crash/hang diagnostic report") { results.append(item) }
        }
        if FileManager.default.fileExists(atPath: systemRoot.path) {
            for url in support.immediateChildren(of: systemRoot) {
                try Task.checkCancellation()
                if let item = support.candidate(url: url, scannerID: id, ruleID: "diagnostic.system.old", category: category, safety: .review, deletionMode: .privileged, requirements: [.privilegedHelper], reason: "System crash/hang diagnostic report") { results.append(item) }
            }
        }
        return results
    }
}

// MARK: - Large and old files

struct LargeOldFileScanner: CleanupScanner {
    let id: CleanupScannerID = "large-old-file"
    let category: CleanupCategory = .largeOldFiles
    private let support = CleanupScannerSupport()
    private let largeThreshold: UInt64 = 500 * 1_024 * 1_024
    private let oldSizeThreshold: UInt64 = 100 * 1_024 * 1_024
    private let oldAge: TimeInterval = 180 * 24 * 60 * 60

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        var results: [CleanupCandidate] = []
        var seen = Set<String>()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        for root in context.requestedRoots where seen.insert(root.path).inserted {
            try Task.checkCancellation()
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                guard !context.isIgnored(url), let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let size = UInt64(max(values.fileSize ?? 0, 0))
                let isLarge = size >= largeThreshold
                let isOldAndMeaningful = size >= oldSizeThreshold && values.contentModificationDate.map { context.now.timeIntervalSince($0) >= oldAge } == true
                guard isLarge || isOldAndMeaningful else { continue }
                if let item = support.candidate(url: url, scannerID: id, ruleID: "largeold.file", category: category, safety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], reason: isLarge ? "Large personal file" : "Large file not modified for at least 180 days", regenerationHint: "Personal files are never part of automatic safe cleanup.") {
                    results.append(item)
                }
            }
        }
        return results
    }
}

// MARK: - Exact duplicates

struct ExactDuplicateScanner: CleanupScanner {
    let id: CleanupScannerID = "duplicate-exact"
    let category: CleanupCategory = .duplicates
    private let support = CleanupScannerSupport()
    private let minimumSize: UInt64 = 1 * 1_024 * 1_024
    private let chunkSize = 64 * 1_024

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let records = try collectFiles(context: context)
        var results: [CleanupCandidate] = []
        for sizeGroup in Dictionary(grouping: records, by: \.size).values where sizeGroup.count > 1 {
            try Task.checkCancellation()
            var partialGroups: [Data: [DuplicateFileRecord]] = [:]
            for record in sizeGroup {
                if let hash = partialHash(record.url, size: record.size) { partialGroups[hash, default: []].append(record) }
            }
            for partialGroup in partialGroups.values where partialGroup.count > 1 {
                try Task.checkCancellation()
                var fullGroups: [Data: [DuplicateFileRecord]] = [:]
                for record in partialGroup {
                    if let hash = fullHash(record.url) { fullGroups[hash, default: []].append(record) }
                }
                for fullGroup in fullGroups.values where fullGroup.count > 1 {
                    let physicalCopies = uniquePhysicalRecords(fullGroup)
                    guard physicalCopies.count > 1 else { continue }
                    let keeper = physicalCopies[0]
                    for duplicate in physicalCopies.dropFirst() {
                        if let item = support.candidate(url: duplicate.url, scannerID: id, ruleID: "duplicate.exact", category: category, displayName: "Duplicate: \(duplicate.url.lastPathComponent)", safety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], reason: "Full SHA-256 matches \(keeper.url.path)", regenerationHint: "Exact duplicates require explicit review; one physical copy is retained as the reference. Hard links are counted only once.") {
                            results.append(item)
                        }
                    }
                }
            }
        }
        return results
    }

    private struct DuplicateFileRecord {
        let url: URL
        let size: UInt64
        let identity: FileIdentity?
    }

    private func uniquePhysicalRecords(_ records: [DuplicateFileRecord]) -> [DuplicateFileRecord] {
        var seenPhysicalIDs = Set<String>()
        var results: [DuplicateFileRecord] = []
        for record in records {
            let key: String
            if let identity = record.identity {
                key = "\(identity.deviceID):\(identity.inode)"
            } else {
                key = "path:\(record.url.standardizedFileURL.path)"
            }
            if seenPhysicalIDs.insert(key).inserted {
                results.append(record)
            }
        }
        return results
    }

    private func collectFiles(context: CleanupScanContext) throws -> [DuplicateFileRecord] {
        var records: [DuplicateFileRecord] = []
        var visited = Set<String>()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        for root in context.requestedRoots where visited.insert(root.path).inserted {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard !context.isIgnored(url), let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let size = UInt64(max(values.fileSize ?? 0, 0))
                guard size >= minimumSize else { continue }
                records.append(DuplicateFileRecord(url: url, size: size, identity: CleanupPathValidator.identity(for: url)))
            }
        }
        return records
    }

    private func partialHash(_ url: URL, size: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            var data = Data()
            data.append(try handle.read(upToCount: chunkSize) ?? Data())
            if size > UInt64(chunkSize) {
                try handle.seek(toOffset: size > UInt64(chunkSize) ? size - UInt64(chunkSize) : 0)
                data.append(try handle.read(upToCount: chunkSize) ?? Data())
            }
            var littleEndianSize = size.littleEndian
            withUnsafeBytes(of: &littleEndianSize) { data.append(contentsOf: $0) }
            return Data(SHA256.hash(data: data))
        } catch { return nil }
    }

    private func fullHash(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
            return Data(hasher.finalize())
        } catch { return nil }
    }
}

// MARK: - Similar images

struct SimilarImageScanner: CleanupScanner {
    let id: CleanupScannerID = "image-similar"
    let category: CleanupCategory = .similarImages
    private let support = CleanupScannerSupport()
    private let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
    private let similarityThreshold: Float = 0.12

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        var buckets: [Int: [ImageFeatureRecord]] = [:]
        for root in context.requestedRoots {
            try Task.checkCancellation()
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                guard supportedExtensions.contains(url.pathExtension.lowercased()), !context.isIgnored(url), let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                if let record = featureRecord(for: url) { buckets[record.aspectBucket, default: []].append(record) }
            }
        }

        var results: [CleanupCandidate] = []
        var selectedPaths = Set<String>()
        for records in buckets.values where records.count > 1 {
            var representatives: [ImageFeatureRecord] = []
            for record in records {
                try Task.checkCancellation()
                var matched: ImageFeatureRecord?
                for representative in representatives {
                    var distance: Float = .greatestFiniteMagnitude
                    if (try? record.feature.computeDistance(&distance, to: representative.feature)) != nil, distance <= similarityThreshold {
                        matched = representative
                        break
                    }
                }
                if let matched {
                    guard selectedPaths.insert(record.url.path).inserted else { continue }
                    if let item = support.candidate(url: record.url, scannerID: id, ruleID: "image.similar", category: category, displayName: "Similar: \(record.url.lastPathComponent)", safety: .review, deletionMode: .trash, requirements: [.explicitConfirmation], reason: "Vision feature print is similar to \(matched.url.lastPathComponent)", regenerationHint: "Visual similarity is advisory only; MemWatch never auto-selects similar photos.") {
                        results.append(item)
                    }
                } else {
                    representatives.append(record)
                }
            }
        }
        return results
    }

    private struct ImageFeatureRecord {
        let url: URL
        let feature: VNFeaturePrintObservation
        let aspectBucket: Int
    }

    private func featureRecord(for url: URL) -> ImageFeatureRecord? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber, height.doubleValue > 0 else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first as? VNFeaturePrintObservation else { return nil }
        let bucket = Int((width.doubleValue / height.doubleValue * 20).rounded())
        return ImageFeatureRecord(url: url, feature: observation, aspectBucket: bucket)
    }
}

// MARK: - Mail attachment cache

struct MailAttachmentScanner: CleanupScanner {
    let id: CleanupScannerID = "mail-attachment"
    let category: CleanupCategory = .mailAttachments
    private let support = CleanupScannerSupport()

    func scan(context: CleanupScanContext) async throws -> [CleanupCandidate] {
        let root = context.homeDirectory.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true)
        var results: [CleanupCandidate] = []
        for url in support.immediateChildren(of: root) {
            try Task.checkCancellation()
            guard !context.isIgnored(url) else { continue }
            if let item = support.candidate(url: url, scannerID: id, ruleID: "mail.attachment.cache", category: category, safety: .review, deletionMode: .permanent, requirements: [.fullDiskAccess, .explicitConfirmation], reason: "Local Mail attachment download cache", regenerationHint: "Mail databases and message stores are never cleanup targets; only the Mail Downloads cache is considered.") {
                results.append(item)
            }
        }
        return results
    }
}

extension CleanupScannerRegistry {
    static var deepAttributionScanners: [any CleanupScanner] {
        [ApplicationLeftoverScanner(), LaunchItemScanner(), DiagnosticReportScanner(), LargeOldFileScanner(), ExactDuplicateScanner(), SimilarImageScanner(), MailAttachmentScanner()]
    }

    static var allScanners: [any CleanupScanner] {
        userSpaceScanners + deepAttributionScanners
    }
}
