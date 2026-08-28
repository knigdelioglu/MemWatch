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
        guard let items = scanResult?.items else { return [] }
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
        guard candidate.safety != .protected, candidate.isPotentiallyDeletable else { return }
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }

    func selectAllReviewItems() {
        selectedIDs.formUnion(reviewItems.map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func dryRunSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .dryRun, confirmedIDs: Set(items.map(\.id)))
    }

    func cleanSelectedConfirmed() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .apply, confirmedIDs: Set(items.map(\.id)))
    }

    func cleanSafeItemsConfirmed() {
        let items = safeItems.filter {
            !$0.requirements.contains(.explicitConfirmation)
        }
        guard !items.isEmpty else { return }
        execute(items: items, mode: .apply, confirmedIDs: [])
    }

    func dryRunSafeItems() {
        let items = safeItems.filter {
            !$0.requirements.contains(.explicitConfirmation)
        }
        guard !items.isEmpty else { return }
        execute(items: items, mode: .dryRun, confirmedIDs: [])
    }

    func ignorePath(for candidate: CleanupCandidate) {
        let rule = CleanupIgnoreRule(kind: .path, value: candidate.url.path, recursive: true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.add(rule)
                await MainActor.run {
                    self.ignoreRules = updated
                    self.selectedIDs.remove(candidate.id)
                }
                await self.runScan()
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    func ignoreRule(_ candidate: CleanupCandidate) {
        let ignore = CleanupIgnoreRule(kind: .rule, value: candidate.ruleID.rawValue)
        addIgnoreAndRescan(ignore)
    }

    func ignoreCategory(_ category: CleanupCategory) {
        let ignore = CleanupIgnoreRule(kind: .category, value: category.rawValue)
        addIgnoreAndRescan(ignore)
    }

    func removeIgnore(_ rule: CleanupIgnoreRule) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.remove(id: rule.id)
                await MainActor.run { self.ignoreRules = updated }
                await self.runScan()
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    func registerHelper() {
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
        guard preferences.privateBackendEnabled,
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
            if !preferences.requestedRootPaths.contains(path) {
                preferences.requestedRootPaths.append(path)
            }
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
            if !preferences.projectRootPaths.contains(path) {
                preferences.projectRootPaths.append(path)
            }
        }
    }

    func removeRequestedRoot(_ path: String) {
        updatePreferences { $0.requestedRootPaths.removeAll { $0 == path } }
    }

    func removeProjectRoot(_ path: String) {
        updatePreferences { $0.projectRootPaths.removeAll { $0 == path } }
    }

    func setPrivateBackendEnabled(_ enabled: Bool) {
        updatePreferences { $0.privateBackendEnabled = enabled }
    }

    // MARK: - Private orchestration

    private func loadPersistentState() async {
        let loadedHistory = await historyStore.load()
        let loadedIgnores = await ignoreStore.load()
        let loadedPreferences = await preferencesStore.load()
        history = loadedHistory
        ignoreRules = loadedIgnores
        preferences = loadedPreferences
        storageSpaceIntelligence = .startupVolume()
        helperService.refreshStatus()
        fullDiskAccessService.refresh()
    }

    private func runScan() async {
        phase = .scanning
        selectedIDs.removeAll()
        storageSpaceIntelligence = .startupVolume()
        fullDiskAccessService.refresh()
        helperService.refreshStatus()

        let ignoreSnapshot = await ignoreStore.snapshot()
        let currentPreferences = await preferencesStore.load()
        preferences = currentPreferences

        var helperAvailable = false
        if currentPreferences.privateBackendEnabled && helperService.isAvailableForCleanup {
            helperAvailable = await helperService.verifyConnection()
        }

        let effectivePolicy: CleanupScanPolicy
        if currentPreferences.privateBackendEnabled {
            effectivePolicy = ignoreSnapshot.policy
        } else {
            effectivePolicy = CleanupScanPolicy(
                ignoredRuleIDs: ignoreSnapshot.policy.ignoredRuleIDs,
                ignoredCategories: ignoreSnapshot.policy.ignoredCategories,
                ignoredScannerIDs: ignoreSnapshot.policy.ignoredScannerIDs.union([CleanupScannerID(rawValue: "privileged-system")])
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
            let result = try await scanEngine.scan(
                context: context,
                policy: effectivePolicy
            ) { [weak self] progress in
                await MainActor.run {
                    self?.scanProgress = progress
                }
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

    private func execute(
        items: [CleanupCandidate],
        mode: CleanupExecutionMode,
        confirmedIDs: Set<UUID>
    ) {
        guard let context = lastContext else { return }
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
            if mode == .apply {
                await self.runScan()
            } else {
                self.phase = .ready
            }
        }
    }

    private func refreshSnapshotsIfAvailable() async {
        guard preferences.privateBackendEnabled,
              helperService.isAvailableForCleanup else {
            snapshots = []
            return
        }
        do {
            snapshots = try await timeMachineBackend.listSnapshots()
        } catch {
            snapshots = []
        }
    }

    private func addIgnoreAndRescan(_ ignore: CleanupIgnoreRule) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.add(ignore)
                self.ignoreRules = updated
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

    private func existingDirectories(_ paths: [String]) -> [URL] {
        paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return url
        }
    }
}
