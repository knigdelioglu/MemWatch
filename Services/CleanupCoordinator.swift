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
    @Published private(set) var applicationActionFeedback: String?
    @Published private(set) var snapshotError: String?
    @Published private(set) var excludedApplicationIDs = Set<String>()
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
    private var applicationActionTask: Task<Void, Never>?
    private var lastContext: CleanupScanContext?
    private let activityGuard = CleanupActivityGuard()
    private var operationGeneration = 0

    init() {
        Task { [weak self] in
            await self?.loadPersistentState()
        }
    }

    deinit {
        scanTask?.cancel()
        executionTask?.cancel()
        applicationActionTask?.cancel()
    }

    var isBusy: Bool {
        switch phase {
        case .scanning, .executing: return true
        case .idle, .ready, .failed: return false
        }
    }

    var isReady: Bool { phase == .ready }

    var safeItems: [CleanupCandidate] {
        scanResult?.items.filter { $0.safety == .safe && $0.isPotentiallyDeletable } ?? []
    }

    private var automaticSafeCandidates: [CleanupCandidate] {
        safeItems.filter { !$0.requirements.contains(.explicitConfirmation) }
    }

    var automaticSafeItems: [CleanupCandidate] {
        automaticSafeCandidates.filter { !isExcludedFromAutomaticCleanup($0) }
    }

    var reviewItems: [CleanupCandidate] {
        scanResult?.items.filter { $0.safety == .review && $0.isPotentiallyDeletable } ?? []
    }

    var protectedItems: [CleanupCandidate] {
        scanResult?.items.filter { $0.safety == .protected || !$0.isPotentiallyDeletable } ?? []
    }

    var safeBytes: UInt64 { scanResult?.safeBytes ?? 0 }
    var automaticSafeBytes: UInt64 {
        automaticSafeItems.reduce(0) { partial, item in
            let (value, overflow) = partial.addingReportingOverflow(item.allocatedBytes)
            return overflow ? UInt64.max : value
        }
    }
    var reviewBytes: UInt64 { scanResult?.reviewBytes ?? 0 }
    var protectedBytes: UInt64 { scanResult?.protectedBytes ?? 0 }
    var reclaimableBytes: UInt64 { scanResult?.reclaimableBytes ?? 0 }

    var selectedItems: [CleanupCandidate] {
        guard preferences.cleanupEnabled, let items = scanResult?.items else { return [] }
        return items.filter {
            selectedIDs.contains($0.id) &&
                $0.safety != .protected &&
                !isExcludedFromAutomaticCleanup($0)
        }
    }

    var selectedBytes: UInt64 {
        selectedItems.reduce(0) { partial, item in
            let (value, overflow) = partial.addingReportingOverflow(item.allocatedBytes)
            return overflow ? UInt64.max : value
        }
    }

    func startScan() {
        scanTask?.cancel()
        executionTask?.cancel()
        applicationActionTask?.cancel()
        excludedApplicationIDs.removeAll()
        operationGeneration &+= 1
        let generation = operationGeneration
        phase = .scanning
        scanTask = Task { [weak self] in
            await self?.runScan(generation: generation)
        }
    }

    func cancelCurrentOperation() {
        scanTask?.cancel()
        executionTask?.cancel()
        applicationActionTask?.cancel()
        phase = scanResult == nil ? .idle : .ready
    }

    func toggleSelection(_ candidate: CleanupCandidate) {
        guard preferences.cleanupEnabled,
              isReady,
              candidate.safety != .protected,
              candidate.isPotentiallyDeletable,
              !isExcludedFromAutomaticCleanup(candidate) else { return }
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }

    func selectAllReviewItems() {
        guard preferences.cleanupEnabled, isReady else { return }
        selectedIDs.formUnion(reviewItems.filter { !isExcludedFromAutomaticCleanup($0) }.map(\.id))
    }

    func clearSelection() {
        guard !isBusy else { return }
        selectedIDs.removeAll()
    }

    var applicationCleanupPlans: [CleanupApplicationCleanupPlan] {
        struct Accumulator {
            var name: String
            var itemIDs = Set<UUID>()
            var allocatedBytes: UInt64 = 0
        }

        var grouped: [String: Accumulator] = [:]
        for item in automaticSafeCandidates {
            guard let name = activityGuard.activeApplicationName(for: item) else { continue }
            let id = applicationCleanupIdentifier(for: item) ?? name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty else { continue }

            var accumulator = grouped[id] ?? Accumulator(name: name)
            accumulator.itemIDs.insert(item.id)
            let (value, overflow) = accumulator.allocatedBytes.addingReportingOverflow(item.allocatedBytes)
            accumulator.allocatedBytes = overflow ? UInt64.max : value
            grouped[id] = accumulator
        }

        return grouped.map { id, value in
            CleanupApplicationCleanupPlan(
                id: id,
                name: value.name,
                itemIDs: value.itemIDs,
                allocatedBytes: value.allocatedBytes
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func isApplicationCleanupEnabled(_ plan: CleanupApplicationCleanupPlan) -> Bool {
        !excludedApplicationIDs.contains(plan.id)
    }

    func setApplicationCleanupEnabled(_ enabled: Bool, for plan: CleanupApplicationCleanupPlan) {
        if enabled {
            excludedApplicationIDs.remove(plan.id)
        } else {
            excludedApplicationIDs.insert(plan.id)
            selectedIDs.subtract(plan.itemIDs)
        }
    }

    func isExcludedFromAutomaticCleanup(_ candidate: CleanupCandidate) -> Bool {
        guard let id = applicationCleanupIdentifier(for: candidate) else { return false }
        return excludedApplicationIDs.contains(id)
    }

    func canRequestApplicationClose(for candidate: CleanupCandidate) -> Bool {
        guard candidate.requirements.contains(.applicationInactive) else { return false }
        if case .active = activityGuard.state(for: candidate) {
            return true
        }
        return false
    }

    func closeApplication(for candidate: CleanupCandidate) {
        guard isReady, canRequestApplicationClose(for: candidate) else { return }

        switch activityGuard.requestTermination(for: candidate) {
        case .terminationRequested(let name):
            applicationActionFeedback = "\(name) için kapatma isteği gönderildi. Kaydedilmemiş değişiklikler varsa macOS onay isteyebilir."
            operationGeneration &+= 1
            let generation = operationGeneration
            scanTask?.cancel()
            executionTask?.cancel()
            applicationActionTask?.cancel()
            phase = .scanning
            applicationActionTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 700_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.runScan(generation: generation)
            }
        case .terminationRejected(let name):
            applicationActionFeedback = "\(name) kapatılamadı. Uygulamayı kendiniz kapatıp Yeniden Tara'yı seçin."
        case .noRunningApplication:
            applicationActionFeedback = "Uygulama artık çalışmıyor. Yeniden taranıyor."
            startScan()
        }
    }

    func dryRunSelected() {
        guard preferences.cleanupEnabled, isReady else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .dryRun, confirmedIDs: Set(items.map(\.id)))
    }

    func cleanSelectedConfirmed() {
        guard preferences.cleanupEnabled, isReady else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .apply, confirmedIDs: Set(items.map(\.id)))
    }

    func cleanSafeItemsConfirmed() {
        guard preferences.cleanupEnabled, isReady else { return }
        let items = automaticSafeItems
        guard !items.isEmpty else { return }
        execute(items: items, mode: .apply, confirmedIDs: [])
    }

    func dryRunSafeItems() {
        guard preferences.cleanupEnabled, isReady else { return }
        let items = automaticSafeItems
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
        guard !isBusy else { return }
        operationGeneration &+= 1
        let generation = operationGeneration
        scanTask?.cancel()
        executionTask?.cancel()
        applicationActionTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.remove(id: rule.id)
                guard self.operationGeneration == generation else { return }
                self.ignoreRules = updated
                await self.runScan(generation: generation)
            } catch {
                guard self.operationGeneration == generation else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func registerHelper() {
        guard preferences.cleanupEnabled, preferences.privilegedOperationsEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let ok = await helperService.register()
            if ok || helperService.state != .requiresApproval {
                NSApp.activate(ignoringOtherApps: true)
            }
            if ok { startScan() }
        }
    }

    func unregisterHelper() {
        helperService.unregister()
        startScan()
    }

    func openHelperApprovalSettings() {
        helperService.openApprovalSettings()
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
              isReady,
              targetBytes > 0 else { return }
        scanTask?.cancel()
        applicationActionTask?.cancel()
        operationGeneration &+= 1
        let generation = operationGeneration
        executionTask?.cancel()
        executionTask = Task { [weak self] in
            guard let self else { return }
            self.phase = .executing(.apply)
            do {
                let before = self.startupVolumeAvailableBytes()
                let startedAt = Date()
                let response = try await self.timeMachineBackend.thinSnapshots(targetBytes: targetBytes)
                guard !Task.isCancelled, self.operationGeneration == generation else { return }
                let after = self.startupVolumeAvailableBytes()
                let verification: CleanupReclaimVerification
                if let before, let after {
                    verification = after > before ? .verified : .noNetIncrease
                } else {
                    verification = .unavailable
                }
                let result = CleanupExecutionItemResult(
                    candidateID: UUID(),
                    ruleID: "timemachine.snapshot",
                    path: "tmutil://local-snapshots",
                    displayName: "Time Machine local snapshots",
                    status: .maintenanceCompleted,
                    affectedBytes: targetBytes,
                    reclaimedBytes: response.reclaimedBytes,
                    message: response.message
                )
                let report = CleanupExecutionReport(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    mode: .apply,
                    results: [result],
                    requestedCount: 1,
                    availableBytesBefore: before,
                    availableBytesAfter: after,
                    reclaimVerification: verification
                )
                self.lastExecution = report
                self.history = try await self.historyStore.append(report: report)
                await self.refreshSnapshotsIfAvailable()
                self.storageSpaceIntelligence = .startupVolume()
                guard self.operationGeneration == generation else { return }
                await self.runScan(generation: generation)
            } catch {
                guard self.operationGeneration == generation else { return }
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
        do {
            let loadedHistory = try await historyStore.load()
            let loadedIgnores = try await ignoreStore.load()
            let loadedPreferences = try await preferencesStore.load()
            history = loadedHistory
            ignoreRules = loadedIgnores
            preferences = loadedPreferences
            backendCapabilities = CleanupBackendCatalog.current(privateBackendsEnabled: loadedPreferences.privateBackendEnabled)
            storageSpaceIntelligence = .startupVolume()
            helperService.refreshStatus()
            if loadedPreferences.privilegedOperationsEnabled {
                _ = await helperService.verifyConnection()
            }
        } catch {
            preferences = .disabled()
            scanResult = nil
            snapshots = []
            lastContext = nil
            phase = .failed(error.localizedDescription)
        }
        fullDiskAccessService.refresh()
    }

    private func runScan(generation requestedGeneration: Int? = nil) async {
        let generation = requestedGeneration ?? operationGeneration
        guard generation == operationGeneration else { return }
        selectedIDs.removeAll()
        storageSpaceIntelligence = .startupVolume()
        fullDiskAccessService.refresh()
        helperService.refreshStatus()

        let ignoreSnapshot: CleanupIgnoreSnapshot
        let currentPreferences: CleanupPreferences
        do {
            ignoreSnapshot = try await ignoreStore.snapshot()
            currentPreferences = try await preferencesStore.load()
        } catch {
            preferences = .disabled()
            scanResult = nil
            snapshots = []
            lastContext = nil
            phase = .failed(error.localizedDescription)
            return
        }
        guard generation == operationGeneration, !Task.isCancelled else { return }
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
        if currentPreferences.privilegedOperationsEnabled {
            helperAvailable = await helperService.verifyConnection()
        }
        guard generation == operationGeneration, !Task.isCancelled else { return }

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
            ignoredExactPaths: ignoreSnapshot.exactPathValues,
            fullDiskAccessAvailable: fullDiskAccessService.isAvailable,
            privilegedHelperAvailable: helperAvailable
        )
        lastContext = context

        do {
            let result = try await scanEngine.scan(context: context, policy: effectivePolicy) { [weak self] progress in
                await self?.receiveScanProgress(progress, generation: generation)
            }
            guard generation == operationGeneration, !Task.isCancelled else { return }
            scanResult = result
            storageSpaceIntelligence = .startupVolume()
            phase = .ready
            await refreshSnapshotsIfAvailable()
        } catch is CancellationError {
            guard generation == operationGeneration else { return }
            phase = scanResult == nil ? .idle : .ready
        } catch {
            guard generation == operationGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func receiveScanProgress(_ progress: CleanupScanProgress, generation: Int) {
        guard generation == operationGeneration else { return }
        scanProgress = progress
    }

    private func execute(
        items: [CleanupCandidate],
        mode: CleanupExecutionMode,
        confirmedIDs: Set<UUID>
    ) {
        guard preferences.cleanupEnabled, isReady, let context = lastContext else { return }
        scanTask?.cancel()
        applicationActionTask?.cancel()
        operationGeneration &+= 1
        let generation = operationGeneration
        executionTask?.cancel()
        executionTask = Task { [weak self] in
            guard let self else { return }
            guard self.operationGeneration == generation else { return }
            self.phase = .executing(mode)
            if mode == .apply {
                await self.prepareApplicationsForCleanup(items)
            }
            guard !Task.isCancelled, self.operationGeneration == generation else { return }
            await self.performExecution(
                candidates: items,
                context: context,
                mode: mode,
                explicitlyConfirmedIDs: confirmedIDs,
                generation: generation
            )
        }
    }

    private func prepareApplicationsForCleanup(_ items: [CleanupCandidate]) async {
        var representatives: [String: (name: String, candidate: CleanupCandidate)] = [:]
        for item in items {
            guard let name = activityGuard.activeApplicationName(for: item) else { continue }
            let id = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            representatives[id] = representatives[id] ?? (name: name, candidate: item)
        }
        guard !representatives.isEmpty else { return }

        let names = representatives.values.map(\.name).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        applicationActionFeedback = "Kapatılacak uygulamalar: \(names.joined(separator: ", ")). Kaydedilmemiş değişiklikler varsa macOS onay isteyebilir."

        for representative in representatives.values {
            _ = activityGuard.requestTermination(for: representative.candidate)
        }

        for _ in 0..<25 {
            guard !Task.isCancelled else { return }
            let stillActive = items.contains { activityGuard.activeApplicationName(for: $0) != nil }
            if !stillActive { return }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
        }

        let unresolved = representatives.values.compactMap { representative in
            activityGuard.activeApplicationName(for: representative.candidate) == nil ? nil : representative.name
        }
        if !unresolved.isEmpty {
            applicationActionFeedback = "Kapatılamayan uygulamalar nedeniyle ilgili cache'ler korunacak: \(unresolved.sorted().joined(separator: ", "))."
        }
    }

    private func performExecution(
        candidates: [CleanupCandidate],
        context: CleanupScanContext,
        mode: CleanupExecutionMode,
        explicitlyConfirmedIDs: Set<UUID>,
        generation: Int
    ) async {
        let report = await deletionEngine.execute(
            candidates: candidates,
            context: context,
            mode: mode,
            explicitlyConfirmedIDs: explicitlyConfirmedIDs
        )
        guard generation == operationGeneration else { return }
        guard !Task.isCancelled || report.isCancelled else { return }
        self.lastExecution = report
        do {
            self.history = try await self.historyStore.append(report: report)
        } catch {
            self.phase = .failed("Cleanup finished, but history could not be saved: \(error.localizedDescription)")
            return
        }

        self.storageSpaceIntelligence = .startupVolume()
        if mode == .apply, !report.isCancelled { await self.runScan(generation: generation) }
        else { self.phase = .ready }
    }

    private func refreshSnapshotsIfAvailable() async {
        guard preferences.cleanupEnabled,
              preferences.privilegedOperationsEnabled,
              helperService.isAvailableForCleanup else {
            snapshots = []
            snapshotError = nil
            return
        }
        snapshotError = nil
        do { snapshots = try await timeMachineBackend.listSnapshots() }
        catch {
            snapshots = []
            snapshotError = error.localizedDescription
        }
    }

    private func addIgnoreAndRescan(_ ignore: CleanupIgnoreRule, removing candidateID: UUID? = nil) {
        guard !isBusy else { return }
        operationGeneration &+= 1
        let generation = operationGeneration
        scanTask?.cancel()
        executionTask?.cancel()
        applicationActionTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await ignoreStore.add(ignore)
                guard self.operationGeneration == generation else { return }
                self.ignoreRules = updated
                if let candidateID { self.selectedIDs.remove(candidateID) }
                await self.runScan(generation: generation)
            } catch {
                guard self.operationGeneration == generation else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func updatePreferences(_ mutation: (inout CleanupPreferences) -> Void) {
        let previous = preferences
        var updated = preferences
        mutation(&updated)
        preferences = updated
        backendCapabilities = CleanupBackendCatalog.current(privateBackendsEnabled: updated.privateBackendEnabled)
        operationGeneration &+= 1
        let generation = operationGeneration
        scanTask?.cancel()
        executionTask?.cancel()
        applicationActionTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await preferencesStore.save(updated)
                guard self.operationGeneration == generation else { return }
                await self.runScan(generation: generation)
            } catch {
                guard self.operationGeneration == generation else { return }
                self.preferences = previous
                self.backendCapabilities = CleanupBackendCatalog.current(privateBackendsEnabled: previous.privateBackendEnabled)
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

    private func applicationCleanupIdentifier(for candidate: CleanupCandidate) -> String? {
        if candidate.category == .xcode {
            return "com.apple.dt.xcode"
        }

        let path = candidate.url.standardizedFileURL.path
        if path.contains("/Library/Application Support/Code/") {
            return "com.microsoft.vscode"
        }
        if path.contains("/Library/Caches/JetBrains") {
            return "com.jetbrains"
        }
        if path.contains("/Library/Caches/com.docker.docker") {
            return "com.docker.docker"
        }
        return CleanupScanPolicy.applicationIdentifier(for: candidate)?.lowercased()
    }

    private func existingDirectories(_ paths: [String]) -> [URL] {
        paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return url
        }
    }

    private func startupVolumeAvailableBytes() -> UInt64? {
        StorageSpaceIntelligence.startupVolume()?.immediateAvailableBytes
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
