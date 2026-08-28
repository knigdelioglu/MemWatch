import SwiftUI

struct CleanupView: View {
    @ObservedObject var coordinator: CleanupCoordinator

    @State private var showSafeConfirmation = false
    @State private var showSelectedConfirmation = false
    @State private var showSnapshotConfirmation = false
    @State private var snapshotTargetBytes: UInt64 = 10 * 1_024 * 1_024 * 1_024
    @State private var showIgnoredItems = false
    @State private var showRoots = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                header
                capabilityCard

                if coordinator.phase == .scanning {
                    progressCard
                }

                if let result = coordinator.scanResult {
                    summaryCard(result)
                    primaryActions
                    categoryList(result)
                } else if coordinator.phase != .scanning {
                    emptyState
                }

                timeMachineCard
                rootsCard
                ignoredCard
                historyCard
            }
            .padding(16)
        }
        .onAppear {
            if coordinator.scanResult == nil, !coordinator.isBusy {
                coordinator.startScan()
            }
        }
        .confirmationDialog(
            "Clean safe items?",
            isPresented: $showSafeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean \(bytes(coordinator.safeBytes))") {
                coordinator.cleanSafeItemsConfirmed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only items classified Safe and not requiring explicit review will be removed. Every target is revalidated immediately before deletion.")
        }
        .confirmationDialog(
            "Clean selected items?",
            isPresented: $showSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean \(bytes(coordinator.selectedBytes))") {
                coordinator.cleanSelectedConfirmed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Review items may include project dependencies, backups, downloads or other data with a rebuild or recovery cost.")
        }
        .confirmationDialog(
            "Thin Time Machine snapshots?",
            isPresented: $showSnapshotConfirmation,
            titleVisibility: .visible
        ) {
            Button("Request \(bytes(snapshotTargetBytes))") {
                coordinator.thinTimeMachineSnapshots(targetBytes: snapshotTargetBytes)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MemWatch will ask tmutil to reclaim the requested amount. It never deletes snapshot storage by manipulating APFS files directly.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Deep Cleanup", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if coordinator.isBusy {
                    Button("Cancel") { coordinator.cancelCurrentOperation() }
                        .buttonStyle(.plain)
                        .font(.caption)
                } else {
                    Button {
                        coordinator.startScan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Scan again")
                }
            }

            Text("Scan first. Delete only after rule, path and file identity validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            capabilityRow(
                symbol: "lock.shield",
                title: "Privileged helper",
                value: helperLabel,
                good: coordinator.helperService.isAvailableForCleanup
            )

            if !coordinator.helperService.isAvailableForCleanup {
                Button("Enable Deep System Cleanup") {
                    coordinator.registerHelper()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Disable Privileged Helper") {
                    coordinator.unregisterHelper()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Divider()

            capabilityRow(
                symbol: "externaldrive.badge.checkmark",
                title: "Full Disk Access",
                value: coordinator.fullDiskAccessService.state.displayName,
                good: coordinator.fullDiskAccessService.isAvailable
            )

            if !coordinator.fullDiskAccessService.isAvailable {
                Button("Open Full Disk Access Settings") {
                    coordinator.openFullDiskAccessSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Recheck permissions") {
                coordinator.refreshPermissionsAndHelper()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func capabilityRow(
        symbol: String,
        title: String,
        value: String,
        good: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(good ? Color.green : Color.orange)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(good ? Color.green : Color.secondary)
        }
    }

    private var helperLabel: String {
        switch coordinator.helperService.state {
        case .enabled: return "Enabled"
        case .notRegistered: return "Not installed"
        case .requiresApproval: return "Needs approval"
        case .notFound: return "Not found"
        case .unavailable: return "Unavailable"
        }
    }

    private var progressCard: some View {
        HStack(spacing: 11) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanning…")
                    .font(.caption.weight(.semibold))
                Text(progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var progressText: String {
        switch coordinator.scanProgress {
        case .preparing: return "Preparing scanners"
        case .scanning(let scannerID, let completed, let total):
            return "\(scannerID.rawValue) · \(completed + 1) / \(max(total, 1))"
        case .evaluating(let scannerID, let candidateCount):
            return "Evaluating \(candidateCount) candidates from \(scannerID.rawValue)"
        case .finishing: return "Applying safety policy"
        }
    }

    private func summaryCard(_ result: CleanupScanResult) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("\(bytes(result.reclaimableBytes)) reclaimable")
                .font(.title3.monospacedDigit().weight(.semibold))

            HStack(spacing: 8) {
                summaryPill("Safe", bytes: result.safeBytes, color: .green)
                summaryPill("Review", bytes: result.reviewBytes, color: .orange)
                summaryPill("Protected", bytes: result.protectedBytes, color: .secondary)
            }

            if !result.issues.isEmpty {
                Text("\(result.issues.count) scan issue\(result.issues.count == 1 ? "" : "s") · inaccessible areas are not counted as zero-byte results")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryPill(_ title: String, bytes value: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(bytes(value))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var primaryActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    coordinator.dryRunSafeItems()
                } label: {
                    Label("Dry Run", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.safeBytes == 0 || coordinator.isBusy)

                Button {
                    showSafeConfirmation = true
                } label: {
                    Label("Clean \(bytes(coordinator.safeBytes))", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.safeBytes == 0 || coordinator.isBusy)
            }

            if !coordinator.selectedIDs.isEmpty {
                HStack(spacing: 8) {
                    Button("Dry Run Selected") { coordinator.dryRunSelected() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Clean Selected") { showSelectedConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)

                Text("\(coordinator.selectedIDs.count) selected · \(bytes(coordinator.selectedBytes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let report = coordinator.lastExecution {
                HStack {
                    Image(systemName: report.failureCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(executionSummary(report))
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(report.failureCount == 0 ? Color.green : Color.orange)
            }
        }
    }

    private func categoryList(_ result: CleanupScanResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Found items")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !coordinator.reviewItems.isEmpty {
                    Button("Select review") { coordinator.selectAllReviewItems() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                }
                if !coordinator.selectedIDs.isEmpty {
                    Button("Clear") { coordinator.clearSelection() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                }
            }

            ForEach(nonEmptyCategories(in: result)) { category in
                DisclosureGroup {
                    VStack(spacing: 6) {
                        ForEach(items(in: category, result: result)) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.top, 7)
                } label: {
                    HStack {
                        Label(category.displayName, systemImage: category.symbolName)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(bytes(categoryBytes(category, result: result)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }

    private func itemRow(_ item: CleanupCandidate) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                coordinator.toggleSelection(item)
            } label: {
                Image(systemName: selectionSymbol(item))
                    .foregroundStyle(safetyColor(item.safety))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(item.safety == .protected)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(item.safety.shortLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(safetyColor(item.safety))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(safetyColor(item.safety).opacity(0.09), in: Capsule())
                }

                Text(item.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let note = item.policyNotes.first {
                    Text(note)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(bytes(item.allocatedBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))

                Menu {
                    Button("Show in Finder") { coordinator.revealInFinder(item) }
                    Divider()
                    Button("Ignore this path") { coordinator.ignorePath(for: item) }
                    Button("Ignore this rule") { coordinator.ignoreRule(item) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
        }
        .padding(9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var timeMachineCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Time Machine snapshots", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(coordinator.snapshots.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if coordinator.snapshots.isEmpty {
                Text(coordinator.helperService.isAvailableForCleanup ? "No local snapshots reported." : "Enable the privileged helper to inspect local snapshots.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Reclaim target", selection: $snapshotTargetBytes) {
                    Text("5 GB").tag(UInt64(5 * 1_024 * 1_024 * 1_024))
                    Text("10 GB").tag(UInt64(10 * 1_024 * 1_024 * 1_024))
                    Text("25 GB").tag(UInt64(25 * 1_024 * 1_024 * 1_024))
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button("Thin snapshots…") { showSnapshotConfirmation = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var rootsCard: some View {
        DisclosureGroup(isExpanded: $showRoots) {
            VStack(alignment: .leading, spacing: 9) {
                rootList(title: "File scan roots", paths: coordinator.preferences.requestedRootPaths) { path in
                    coordinator.removeRequestedRoot(path)
                }
                Button("Add file scan folder…") { coordinator.chooseRequestedRoot() }
                    .buttonStyle(.plain)
                    .font(.caption)

                Divider()

                rootList(title: "Project roots", paths: coordinator.preferences.projectRootPaths) { path in
                    coordinator.removeProjectRoot(path)
                }
                Button("Add project folder…") { coordinator.chooseProjectRoot() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(.top, 9)
        } label: {
            Label("Scan roots", systemImage: "folder.badge.gearshape")
                .font(.subheadline.weight(.semibold))
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func rootList(
        title: String,
        paths: [String],
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(paths, id: \.self) { path in
                HStack {
                    Text(abbreviated(path))
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                    Spacer()
                    Button { remove(path) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ignoredCard: some View {
        DisclosureGroup(isExpanded: $showIgnoredItems) {
            VStack(spacing: 6) {
                if coordinator.ignoreRules.isEmpty {
                    Text("No cleanup ignores")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.ignoreRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.kind.rawValue.capitalized)
                                    .font(.caption2.weight(.semibold))
                                Text(abbreviated(rule.value))
                                    .font(.system(size: 9).monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button { coordinator.removeIgnore(rule) } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Ignored items (\(coordinator.ignoreRules.count))", systemImage: "eye.slash")
                .font(.subheadline.weight(.semibold))
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent cleanup", systemImage: "clock")
                .font(.subheadline.weight(.semibold))

            if coordinator.history.isEmpty {
                Text("No cleanup history yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.history.prefix(4)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.mode == .dryRun ? "Dry run" : "Cleanup")
                                .font(.caption.weight(.medium))
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.mode == .dryRun ? "\(entry.requestedCount) checked" : bytes(entry.reclaimedBytes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(entry.failedCount == 0 ? Color.secondary : Color.orange)
                    }
                }
            }
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No cleanup scan yet")
                .font(.subheadline.weight(.semibold))
            Button("Scan Now") { coordinator.startScan() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func nonEmptyCategories(in result: CleanupScanResult) -> [CleanupCategory] {
        CleanupCategory.allCases.filter { category in
            result.items.contains { $0.category == category }
        }
    }

    private func items(in category: CleanupCategory, result: CleanupScanResult) -> [CleanupCandidate] {
        result.items.filter { $0.category == category }
    }

    private func categoryBytes(_ category: CleanupCategory, result: CleanupScanResult) -> UInt64 {
        items(in: category, result: result).reduce(0) { partial, item in
            let (value, overflow) = partial.addingReportingOverflow(item.allocatedBytes)
            return overflow ? UInt64.max : value
        }
    }

    private func selectionSymbol(_ item: CleanupCandidate) -> String {
        if item.safety == .protected { return "lock.fill" }
        return coordinator.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle"
    }

    private func safetyColor(_ safety: CleanupSafetyLevel) -> Color {
        switch safety {
        case .safe: return .green
        case .review: return .orange
        case .protected: return .secondary
        }
    }

    private func executionSummary(_ report: CleanupExecutionReport) -> String {
        if report.mode == .dryRun {
            return "Dry run: \(report.results.filter { $0.status == .wouldRemove }.count) validated, \(report.failureCount) blocked"
        }
        return "Removed \(report.successfulCount) items · \(bytes(report.reclaimedBytes)) · \(report.failureCount) failed"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private extension CleanupSafetyLevel {
    var shortLabel: String {
        switch self {
        case .safe: return "SAFE"
        case .review: return "REVIEW"
        case .protected: return "PROTECTED"
        }
    }
}

private extension CleanupCategory {
    var displayName: String {
        switch self {
        case .userCaches: return "User Caches"
        case .systemCaches: return "System Caches"
        case .logs: return "Logs & Diagnostics"
        case .xcode: return "Xcode"
        case .developer: return "Developer Tools"
        case .projectArtifacts: return "Project Artifacts"
        case .aiArtifacts: return "AI & Local Models"
        case .applicationLeftovers: return "Application Leftovers"
        case .launchItems: return "Launch Items"
        case .iosBackups: return "iPhone / iPad Backups"
        case .downloads: return "Downloads & Installers"
        case .trash: return "Trash"
        case .largeOldFiles: return "Large & Old Files"
        case .duplicates: return "Exact Duplicates"
        case .similarImages: return "Similar Images"
        case .mailAttachments: return "Mail Attachments"
        case .snapshots: return "Snapshots"
        case .maintenance: return "Maintenance"
        }
    }

    var symbolName: String {
        switch self {
        case .userCaches, .systemCaches: return "shippingbox"
        case .logs: return "doc.text.magnifyingglass"
        case .xcode: return "hammer"
        case .developer: return "terminal"
        case .projectArtifacts: return "folder.badge.gearshape"
        case .aiArtifacts: return "brain"
        case .applicationLeftovers: return "app.badge.checkmark"
        case .launchItems: return "power"
        case .iosBackups: return "iphone"
        case .downloads: return "arrow.down.circle"
        case .trash: return "trash"
        case .largeOldFiles: return "doc.badge.clock"
        case .duplicates: return "doc.on.doc"
        case .similarImages: return "photo.stack"
        case .mailAttachments: return "paperclip"
        case .snapshots: return "clock.arrow.circlepath"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
}
