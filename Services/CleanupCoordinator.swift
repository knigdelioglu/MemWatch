import AppKit
import Combine
import Foundation

@MainActor
enum CleanupCoordinatorPhase: Equatable {
    case idle
    case scanning
    case ready
    case executing(CleanupExecutionMode)
    case failed(String)
}

@MainActor
final class CleanupCoordinator: ObservableObject {
    @Published private(set) var phase: CleanupCoordinatorPhase = .idle
    @Published private(set) var scanProgress: CleanupScanProgress = .preparing
    @Published private(set) var scanResult: CleanupScanResult?
    @Published private(set) var lastExecution: CleanupExecutionReport?
    @Published private(set) var history: [CleanupHistoryEntry] = []
    @Published private(set) var ignoreRules: [CleanupIgnoreRule] = []
    @Published private(set) var preferences: CleanupPreferences = .defaults()
    @Published private(set) var snapshots: [PrivilegedScannedItem] = []
    @Published private(set) var storageSpaceIntelligence: StorageSpaceIntelligence? = .startupVolume()
    @Published private(set) var backendCapabilities: [CleanupBackendCapability] = CleanupBackendCatalog.current(privateBackendsEnabled: true)
    @Published var selectedIDs = Set<UUID>()

    let helperService = PrivilegedHelperService()
    let fullDiskAccessService = FullDiskAccessService()

    private let scanEngine = CleanupScanEngine()
    private let deletionEngine = CleanupDeletionEngine()
    private let ignoreStore = CleanupIgnoreStore()
    private let historyStore = CleanupHistoryStore()
    private let preferencesStore = CleanupPreferencesStore()
    private let timeMachineBackend = TimeMachineSnapshotBackend()

    private var scanTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var lastContext: CleanupScanContext?

    init() {
        Task { [weak self] in
            await self?.loadPersistentState()
        }
    }

    deinit {
        scanTask?.cancel()
        executionTask?.cancel()
    }

    var isBusy: Bool {
        switch phase {
        case .scanning, .executing: return true
        case .idle, .ready, .failed: return false
        }
    }

    var safeItems: [CleanupCandidate] {
        scanResult?.items.filter { $0.safety == .safe && $0.isPotentiallyDeletable } ?? []
    }

    var reviewItems: [CleanupCandidate] {
        scanResult?.items.filter { $0.safety == .review && $0.isPotentiallyDeletable } ?? []
    }

    var protectedItems: [CleanupCandidate] {
        scanResult?.items.filter { $0.safety == .protected || !$0.isPotentiallyDeletable } ?? []
    }

    var safeBytes: UInt64 { scanResult?.safeBytes ?? 0 }
    var reviewBytes: UInt64 { scanResult?.reviewBytes ?? 0 }
    var protectedBytes: UInt64 { scanResult?.protectedBytes ?? 0 }
    var reclaimableBytes: UInt64 { scanResult?.reclaimableBytes ?? 0 }

    var selectedItems: [CleanupCandidate] {
        guard preferences.cleanupEnabled, let items = scanResult?.items else { return [] }
        return items.filter { selectedIDs.contains($0.id) && $0.safety != .protected }
    }

    var selectedBytes: UInt64 {
        selectedItems.reduce(0) { partial, item in
            let (value, overflow) = partial.addingReportingOverflow(item.allocatedBytes)
            return overflow ? UInt64.max : value
        }
    }

    func startScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.runScan()
        }
    }

    func cancelCurrentOperation() {
        scanTask?.cancel()
        executionTask?.cancel()
    }

    func toggleSelection(_ candidate: CleanupCandidate) {
        guard preferences.cleanupEnabled, candidate.safety != .protected, candidate.isPotentiallyDeletable else { return }
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }

    func selectAllReviewItems() {
        guard preferences.cleanupEnabled else { return }
        selectedIDs.formUnion(reviewItems.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func dryRunSelected() {
        guard preferences.cleanupEnabled else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .dryRun, confirmedIDs: Set(items.map(\.id)))
    }

    func cleanSelectedConfirmed() {
        guard preferences.cleanupEnabled else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .apply, confirmedIDs: Set(items.map(\.id)))
    }

    func cleanSafeItemsConfirmed() {
        guard preferences.cleanupEnabled else { return }
        let items = safeItems.filter { !$0.requirements.contains(.explicitConfirmation) }
        guard !items.isEmpty else { return }
        execute(items: items, mode: .apply, confirmedIDs: [])
    }

    func dryRunSafeItems() {
        guard preferences.cleanupEnabled else { return }
        let items = safeItems.filter { !$0.requirements.contains(.explicitConfirmation) }
        guard !items.isEmpty else { return }
        execute(items: items, mode: .dryRun, confirmedIDs: [])
    }

    func ignorePath(for candidate: CleanupCandidate) {
        addIgnoreAndRescan(CleanupIgnoreRule(kind: .path, value: candidate.url.path, recursive: true), removing: candidate.id)
    }

    func ignoreProject(for candidate: CleanupCandidate) {
        guard let root = projectRoot(containing: candidate.url) else { return }
        addIgnoreAndRescan(CleanupIgnoreRule(kind: .project, value: root, recursive: true), removing: candidate.id)
    }

    func ignoreApplication(for candidate: CleanupCandidate) {
        guard let identifier = CleanupScanPolicy.applicationIdentifier(for: candidate) else { return }
        addIgnoreAndRescan(CleanupIgnoreRule(kind: .application, value: identifier), removing: candidate.id)
    }

    func canIgnoreProject(_ candidate: CleanupCandidate) -> Bool {
        projectRoot(containing: candidate.url) != nil
    }

    func canIgnoreApplication(_ candidate: CleanupCandidate) -> Bool {
        CleanupScanPolicy.applicationIdentifier(for: candidate) != nil
    }

    func ignoreRule(_ candidate: CleanupCandidate) {
        addIgnoreAndRescan(CleanupIgnoreRule(kind: .rule, value: candidate.ruleID.rawValue), removing: candidate.id)
    }

    func ignoreCategory(_ category: CleanupCategory) {
        addIgnoreAndRescan(CleanupIgnoreRule(kind: .category, value: category.rawValue))
    }

    func removeIgnore(_ rule: CleanupIgnoreRule) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.remove(id: rule.id)
                self.ignoreRules = updated
                await self.runScan()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func registerHelper() {
        guard preferences.cleanupEnabled, preferences.privilegedOperationsEnabled else { return }
        helperService.register()
        Task { [weak self] in
            guard let self else { return }
            let ok = await helperService.verifyConnection()
            if ok { await runScan() }
        }
    }

    func unregisterHelper() {
        helperService.unregister()
        startScan()
    }

    func openFullDiskAccessSettings() {
        fullDiskAccessService.openSettings()
    }

    func refreshPermissionsAndHelper() {
        fullDiskAccessService.refresh()
        helperService.refreshStatus()
        startScan()
    }

    func thinTimeMachineSnapshots(targetBytes: UInt64) {
        guard preferences.cleanupEnabled,
              preferences.privilegedOperationsEnabled,
              helperService.isAvailableForCleanup,
              targetBytes > 0 else { return }
        executionTask?.cancel()
        executionTask = Task { [weak self] in
            guard let self else { return }
            self.phase = .executing(.apply)
            do {
                _ = try await self.timeMachineBackend.thinSnapshots(targetBytes: targetBytes)
                await self.refreshSnapshotsIfAvailable()
                self.storageSpaceIntelligence = .startupVolume()
                await self.runScan()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func revealInFinder(_ candidate: CleanupCandidate) {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
    }

    func chooseRequestedRoot() {
        let panel = NSOpenPanel()
        panel.title = "Add Cleanup Scan Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updatePreferences { preferences in
            let path = url.standardizedFileURL.path
            if !preferences.requestedRootPaths.contains(path) { preferences.requestedRootPaths.append(path) }
        }
    }

    func chooseProjectRoot() {
        let panel = NSOpenPanel()
        panel.title = "Add Project Root"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updatePreferences { preferences in
            let path = url.standardizedFileURL.path
            if !preferences.projectRootPaths.contains(path) { preferences.projectRootPaths.append(path) }
        }
    }

    func removeRequestedRoot(_ path: String) {
        updatePreferences { $0.requestedRootPaths.removeAll { $0 == path } }
    }

    func removeProjectRoot(_ path: String) {
        updatePreferences { $0.projectRootPaths.removeAll { $0 == path } }
    }

    func setCleanupEnabled(_ enabled: Bool) {
        if !enabled { cancelCurrentOperation(); selectedIDs.removeAll() }
        updatePreferences { $0.cleanupEnabled = enabled }
    }

    func setPrivilegedOperationsEnabled(_ enabled: Bool) {
        updatePreferences { $0.privilegedOperationsEnabled = enabled }
    }

    func setPrivateBackendEnabled(_ enabled: Bool) {
        updatePreferences { $0.privateBackendEnabled = enabled }
    }

    private func loadPersistentState() async {
        let loadedHistory = await historyStore.load()
        let loadedIgnores = await ignoreStore.load()
        let loadedPreferences = await preferencesStore.load()
        history = loadedHistory
        ignoreRules = loadedIgnores
        preferences = loadedPreferences
        backendCapabilities = CleanupBackendCatalog.current(privateBackendsEnabled: loadedPreferences.privateBackendEnabled)
        storageSpaceIntelligence = .startupVolume()
        helperService.refreshStatus()
        fullDiskAccessService.refresh()
    }

    private func runScan() async {
        selectedIDs.removeAll()
        storageSpaceIntelligence = .startupVolume()
        fullDiskAccessService.refresh()
        helperService.refreshStatus()

        let ignoreSnapshot = await ignoreStore.snapshot()
        let currentPreferences = await preferencesStore.load()
        preferences = currentPreferences
        backendCapabilities = CleanupBackendCatalog.current(privateBackendsEnabled: currentPreferences.privateBackendEnabled)

        guard currentPreferences.cleanupEnabled else {
            scanResult = nil
            snapshots = []
            lastContext = nil
            phase = .idle
            return
        }

        phase = .scanning
        var helperAvailable = false
        if currentPreferences.privilegedOperationsEnabled && helperService.isAvailableForCleanup {
            helperAvailable = await helperService.verifyConnection()
        }

        let effectivePolicy: CleanupScanPolicy
        if currentPreferences.privilegedOperationsEnabled {
            effectivePolicy = ignoreSnapshot.policy
        } else {
            effectivePolicy = CleanupScanPolicy(
                ignoredRuleIDs: ignoreSnapshot.policy.ignoredRuleIDs,
                ignoredCategories: ignoreSnapshot.policy.ignoredCategories,
                ignoredScannerIDs: ignoreSnapshot.policy.ignoredScannerIDs.union([CleanupScannerID(rawValue: "privileged-system")]),
                ignoredProjectPaths: ignoreSnapshot.policy.ignoredProjectPaths,
                ignoredApplicationIdentifiers: ignoreSnapshot.policy.ignoredApplicationIdentifiers
            )
        }

        let requestedRoots = existingDirectories(currentPreferences.requestedRootPaths)
        let projectRoots = existingDirectories(currentPreferences.projectRootPaths)
        let context = CleanupScanContext(
            requestedRoots: requestedRoots,
            projectRoots: projectRoots,
            ignoredPaths: ignoreSnapshot.pathValues,
            fullDiskAccessAvailable: fullDiskAccessService.isAvailable,
            privilegedHelperAvailable: helperAvailable
        )
        lastContext = context

        do {
            let result = try await scanEngine.scan(context: context, policy: effectivePolicy) { [weak self] progress in
                await self?.receiveScanProgress(progress)
            }
            if Task.isCancelled { return }
            scanResult = result
            storageSpaceIntelligence = .startupVolume()
            phase = .ready
            await refreshSnapshotsIfAvailable()
        } catch is CancellationError {
            phase = scanResult == nil ? .idle : .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func receiveScanProgress(_ progress: CleanupScanProgress) {
        scanProgress = progress
    }

    private func execute(
        items: [CleanupCandidate],
        mode: CleanupExecutionMode,
        confirmedIDs: Set<UUID>
    ) {
        guard preferences.cleanupEnabled, let context = lastContext else { return }
        executionTask?.cancel()
        executionTask = Task { [weak self] in
            guard let self else { return }
            self.phase = .executing(mode)
            let report = await self.deletionEngine.execute(
                candidates: items,
                context: context,
                mode: mode,
                explicitlyConfirmedIDs: confirmedIDs
            )
            self.lastExecution = report
            do {
                self.history = try await self.historyStore.append(report: report)
            } catch {
                self.phase = .failed("Cleanup finished, but history could not be saved: \(error.localizedDescription)")
                return
            }

            self.storageSpaceIntelligence = .startupVolume()
            if mode == .apply { await self.runScan() }
            else { self.phase = .ready }
        }
    }

    private func refreshSnapshotsIfAvailable() async {
        guard preferences.cleanupEnabled,
              preferences.privilegedOperationsEnabled,
              helperService.isAvailableForCleanup else {
            snapshots = []
            return
        }
        do { snapshots = try await timeMachineBackend.listSnapshots() }
        catch { snapshots = [] }
    }

    private func addIgnoreAndRescan(_ ignore: CleanupIgnoreRule, removing candidateID: UUID? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.add(ignore)
                self.ignoreRules = updated
                if let candidateID { self.selectedIDs.remove(candidateID) }
                await self.runScan()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func updatePreferences(_ mutation: (inout CleanupPreferences) -> Void) {
        var updated = preferences
        mutation(&updated)
        preferences = updated
        backendCapabilities = CleanupBackendCatalog.current(privateBackendsEnabled: updated.privateBackendEnabled)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await preferencesStore.save(updated)
                await self.runScan()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func projectRoot(containing url: URL) -> String? {
        preferences.projectRootPaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { CleanupPathValidator.path(url.path, isEqualToOrDescendantOf: $0) }
            .max(by: { $0.count < $1.count })
    }

    private func existingDirectories(_ paths: [String]) -> [URL] {
        paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return url
        }
    }
}

enum CleanupBackendKind: String, Sendable {
    case publicAPI
    case systemCLI
    case directFilesystem
    case privateUndocumented
}

struct CleanupBackendCapability: Identifiable, Equatable, Sendable {
    let id: String
    let kind: CleanupBackendKind
    let title: String
    let available: Bool
    let enabled: Bool
    let detail: String
}

protocol CleanupCapabilityBackend: Sendable {
    var capability: CleanupBackendCapability { get }
}

private struct DirectFilesystemCapabilityBackend: CleanupCapabilityBackend {
    let capability = CleanupBackendCapability(
        id: "filesystem",
        kind: .directFilesystem,
        title: "Validated filesystem cleanup",
        available: true,
        enabled: true,
        detail: "Canonical path, ownership and file identity are revalidated at deletion time."
    )
}

private struct TimeMachineCLICapabilityBackend: CleanupCapabilityBackend {
    var capability: CleanupBackendCapability {
        let available = FileManager.default.isExecutableFile(atPath: "/usr/bin/tmutil")
        return CleanupBackendCapability(
            id: "tmutil",
            kind: .systemCLI,
            title: "Time Machine system backend",
            available: available,
            enabled: available,
            detail: available ? "Uses Apple's tmutil rather than raw APFS snapshot deletion." : "tmutil is unavailable on this macOS installation."
        )
    }
}

private struct APFSCapacityCapabilityBackend: CleanupCapabilityBackend {
    var capability: CleanupBackendCapability {
        let available = StorageSpaceIntelligence.startupVolume() != nil
        return CleanupBackendCapability(
            id: "apfs-capacity",
            kind: .publicAPI,
            title: "APFS capacity intelligence",
            available: available,
            enabled: available,
            detail: "Uses public volume capacity-for-important/opportunistic-usage keys; no unsafe forced purge operation."
        )
    }
}

private struct PrivateCompatibilityCapabilityBackend: CleanupCapabilityBackend {
    let privateBackendsEnabled: Bool

    var capability: CleanupBackendCapability {
        CleanupBackendCapability(
            id: "private-runtime",
            kind: .privateUndocumented,
            title: "Private compatibility backend",
            available: false,
            enabled: false,
            detail: privateBackendsEnabled
                ? "Enabled by policy, but no undocumented backend is selected because current public/CLI backends cover the implemented operations."
                : "Disabled by the private-backend kill switch."
        )
    }
}

enum CleanupBackendCatalog {
    static func current(privateBackendsEnabled: Bool) -> [CleanupBackendCapability] {
        let backends: [any CleanupCapabilityBackend] = [
            DirectFilesystemCapabilityBackend(),
            TimeMachineCLICapabilityBackend(),
            APFSCapacityCapabilityBackend(),
            PrivateCompatibilityCapabilityBackend(privateBackendsEnabled: privateBackendsEnabled)
        ]
        return backends.map(\.capability)
    }
}
