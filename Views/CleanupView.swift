import AppKit
import SwiftUI

struct CleanupView: View {
    @ObservedObject var coordinator: CleanupCoordinator
    var showsNavigation = true
    var onOpenOverview: () -> Void = {}
    var onOpenDisplays: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @State private var showSafeConfirmation = false
    @State private var showSelectedConfirmation = false
    @State private var showSnapshotConfirmation = false
    @State private var showSafetyDetails = false
    @State private var snapshotTargetBytes: UInt64 = 10 * 1_024 * 1_024 * 1_024
    @State private var showIgnoredItems = false
    @State private var showRoots = false
    @State private var showAdvancedDetails = false
    @State private var showScanIssues = false
    @State private var showApplicationDetails = false

    var body: some View {
        HStack(spacing: 0) {
            if showsNavigation {
                WindowSidebar(
                    selection: .cleanup,
                    onOpenOverview: onOpenOverview,
                    onOpenCleanup: {},
                    onOpenDisplays: onOpenDisplays,
                    onOpenSettings: onOpenSettings
                )
            }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header

                        if coordinator.phase == .scanning { progressCard }
                        if case .failed(let message) = coordinator.phase { failureCard(message) }

                        if let result = coordinator.scanResult {
                            summaryCard(result)
                            if !result.items.isEmpty {
                                DisclosureGroup("How cleanup safety labels work", isExpanded: $showSafetyDetails) {
                                    deletionScopeCard
                                        .padding(10)
                                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .font(.caption.weight(.medium))
                                categoryList(result)
                            }
                            let relevantIssues = userRelevantIssues(in: result.issues)
                            if !relevantIssues.isEmpty { scanIssuesCard(relevantIssues) }
                        } else if coordinator.phase != .scanning, !isFailedPhase {
                            emptyState
                        }

                        if needsPermissionAttention { permissionNotice }
                        advancedDetails
                    }
                    .padding(20)
                }

                bottomActionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            showAdvancedDetails = false
            showScanIssues = false
            showApplicationDetails = false
            showSafetyDetails = false
            if coordinator.scanResult == nil, !coordinator.isBusy {
                coordinator.startScan()
            }
        }
        .confirmationDialog(
            "Clean only safe items?",
            isPresented: $showSafeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean \(bytes(coordinator.automaticSafeBytes)) Safely") {
                coordinator.cleanSafeItemsConfirmed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only items classified SAFE and not requiring separate confirmation are removed. REVIEW and PROTECTED items are not deleted by this action. Every target is revalidated immediately before removal.")
        }
        .confirmationDialog(
            "Clean selected items?",
            isPresented: $showSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean selected items (\(bytes(coordinator.selectedBytes)))") {
                coordinator.cleanSelectedConfirmed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("REVIEW items can include project dependencies, backups, downloads, or other data with a recovery cost. Only selected items are processed.")
        }
        .confirmationDialog(
            "Thin Time Machine snapshots?",
            isPresented: $showSnapshotConfirmation,
            titleVisibility: .visible
        ) {
            Button("Request \(bytes(snapshotTargetBytes)) of space") {
                coordinator.thinTimeMachineSnapshots(targetBytes: snapshotTargetBytes)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MemWatch uses tmutil to request the selected amount of free space. It does not directly delete or modify APFS snapshot files.")
        }
    }

    private func isAutomaticSafe(_ item: CleanupCandidate) -> Bool {
        coordinator.automaticSafeItems.contains { $0.id == item.id }
    }

    private var isFailedPhase: Bool {
        if case .failed = coordinator.phase { return true }
        return false
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cleanup")
                    .font(.title2.weight(.semibold))
                Text("Find and safely remove unnecessary files to free up space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.isBusy {
                Button("Cancel") { coordinator.cancelCurrentOperation() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
        }
    }

    private var needsPermissionAttention: Bool {
        guard coordinator.preferences.cleanupEnabled,
              coordinator.preferences.privilegedOperationsEnabled else { return false }
        return !coordinator.helperService.isAvailableForCleanup ||
            !coordinator.fullDiskAccessService.isAvailable
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
                Text("Cleanup options")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle(
                "Temizleme etkin",
                isOn: Binding(
                    get: { coordinator.preferences.cleanupEnabled },
                    set: { coordinator.setCleanupEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption.weight(.semibold))

            Toggle(
                "Privileged system operations",
                isOn: Binding(
                    get: { coordinator.preferences.privilegedOperationsEnabled },
                    set: { coordinator.setPrivilegedOperationsEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption.weight(.semibold))
            .disabled(!coordinator.preferences.cleanupEnabled)

            Toggle(
                "Private compatibility methods",
                isOn: Binding(
                    get: { coordinator.preferences.privateBackendEnabled },
                    set: { coordinator.setPrivateBackendEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption.weight(.semibold))
            .disabled(!coordinator.preferences.cleanupEnabled)

            Text("Private compatibility methods may rely on undocumented macOS behavior.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            capabilityRow(
                symbol: "lock.shield",
                title: "Privileged Helper",
                value: helperLabel,
                good: coordinator.helperService.isAvailableForCleanup
            )

            if coordinator.helperService.isRegistering {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing privileged helper…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if coordinator.helperService.state == .requiresApproval {
                Button("Approve in System Settings") {
                    coordinator.openHelperApprovalSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if !coordinator.helperService.isAvailableForCleanup {
                Button(coordinator.helperService.state == .enabled ? "Retry Connection" : "Enable Deep System Cleanup") {
                    coordinator.registerHelper()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!coordinator.preferences.cleanupEnabled || !coordinator.preferences.privilegedOperationsEnabled)
            } else {
                Button("Disable Privileged Helper") {
                    coordinator.unregisterHelper()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let helperError = coordinator.helperService.lastError,
               !helperError.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Could not enable the privileged helper. Try again or check System Settings.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(helperError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Divider()

            capabilityRow(
                symbol: "externaldrive.badge.checkmark",
                title: "Full Disk Access",
                value: fullDiskAccessLabel,
                good: coordinator.fullDiskAccessService.isAvailable
            )

            if !coordinator.fullDiskAccessService.isAvailable {
                Button("Open Full Disk Access Settings") {
                    coordinator.openFullDiskAccessSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Refresh Permissions") {
                coordinator.refreshPermissionsAndHelper()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var storageIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("APFS Storage", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))

            if let capacity = coordinator.storageSpaceIntelligence {
                capacityRow("Available now", value: capacity.immediateAvailableBytes)
                capacityRow("Purgeable by macOS", value: capacity.purgeableEstimateBytes)
                capacityRow("Total Available", value: capacity.importantUsageAvailableBytes)
                Text("Space managed by macOS is excluded from cleanup totals.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Could not retrieve APFS capacity details for the startup disk.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func capacityRow(_ title: String, value: UInt64) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(bytes(value))
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
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
        if coordinator.helperService.isRegistering { return "Installing…" }

        switch coordinator.helperService.state {
        case .enabled:
            return coordinator.helperService.connectionVerified ? "Enabled" : "Connection not verified"
        case .notRegistered: return "Not installed"
        case .requiresApproval: return "Approval required"
        case .notFound: return "Not found"
        case .unavailable: return "Unavailable"
        case .installing: return "Installing…"
        }
    }

    private var fullDiskAccessLabel: String {
        switch coordinator.fullDiskAccessService.state {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .unknown: return "Unknown"
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Some system locations may not be scanned", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text("You can clean the current results. Grant the missing permission for a more complete scan.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if coordinator.helperService.isRegistering {
                    ProgressView()
                        .controlSize(.small)
                    Text("Enabling privileged helper…")
                        .font(.caption2)
                } else if coordinator.helperService.state == .requiresApproval {
                    Button("Approve Helper") { coordinator.openHelperApprovalSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if !coordinator.helperService.isAvailableForCleanup {
                    Button("Enable System Scan") { coordinator.registerHelper() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if !coordinator.fullDiskAccessService.isAvailable {
                    Button("Grant Disk Access") { coordinator.openFullDiskAccessSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()
            }

            if let helperError = coordinator.helperService.lastError,
               !helperError.isEmpty,
               !coordinator.helperService.isRegistering {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Could not install privileged helper", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(helperError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(11)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var advancedDetails: some View {
        DisclosureGroup(isExpanded: $showAdvancedDetails) {
            VStack(alignment: .leading, spacing: 12) {
                capabilityCard
                Divider()
                storageIntelligenceCard
                Divider()
                timeMachineCard
                Divider()
                rootsCard
                Divider()
                ignoredCard
                Divider()
                historyCard
            }
            .padding(.top, 10)
        } label: {
            Label("Settings and details", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding(.vertical, 8)
    }

    private var progressText: String {
        switch coordinator.scanProgress {
        case .preparing:
            return "Preparing"
        case .scanning(_, let completed, let total):
            return "Checking files · \(completed + 1) / \(max(total, 1))"
        case .evaluating(_, let candidateCount):
            return "Reviewing \(candidateCount) items for safety"
        case .finishing:
            return "Finishing final checks"
        }
    }

    private func summaryCard(_: CleanupScanResult) -> some View {
        HStack(spacing: 18) {
            reclaimableGauge

            VStack(alignment: .leading, spacing: 7) {
                Text(coordinator.isReady ? "Scan Complete" : "Scan in progress")
                    .font(.headline)
                Text("\(coordinator.scanResult?.items.count ?? 0) items across \(coordinator.scanResult.map { nonEmptyCategories(in: $0).count } ?? 0) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Only recreatable items are included in the safe total. Every target is revalidated before removal.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !coordinator.applicationCleanupPlans.isEmpty {
                    applicationCleanupCard
                }
            }
            Spacer(minLength: 0)
            Button("Rescan") { coordinator.startScan() }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isBusy)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cleanup scan summary")
    }

    private var reclaimableGauge: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: coordinator.reclaimableBytes == 0 ? 0 : min(1, Double(coordinator.automaticSafeBytes) / Double(max(coordinator.reclaimableBytes, 1))))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(bytes(coordinator.automaticSafeBytes))
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("reclaimable")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, height: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bytes(coordinator.automaticSafeBytes)) safely reclaimable")
    }

    private var bottomActionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(coordinator.selectedItems.isEmpty
                     ? "\(bytes(coordinator.automaticSafeBytes)) safe to clean"
                     : "\(bytes(coordinator.selectedBytes)) selected")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !coordinator.selectedItems.isEmpty {
                    Button("Review in Finder") {
                        if let item = coordinator.selectedItems.first { coordinator.revealInFinder(item) }
                    }
                    .disabled(coordinator.isBusy)
                    .help("Show the first selected item in Finder")
                    Button("Clean Selected") { showSelectedConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!coordinator.isReady)
                    Menu {
                        Button("Preview Safe Cleanup") { coordinator.dryRunSafeItems() }
                            .disabled(coordinator.automaticSafeBytes == 0 || !coordinator.isReady)
                        Button("Clean Safe Items") { showSafeConfirmation = true }
                            .disabled(coordinator.automaticSafeBytes == 0 || !coordinator.isReady)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(minWidth: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("More cleanup actions")
                } else {
                    Button("Preview Safe Cleanup") { coordinator.dryRunSafeItems() }
                        .disabled(coordinator.automaticSafeBytes == 0 || !coordinator.isReady)
                    Button("Clean Safe Items") { showSafeConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(coordinator.automaticSafeBytes == 0 || !coordinator.isReady)
                }
            }

            if let report = coordinator.lastExecution {
                Label(executionSummary(report), systemImage: report.failureCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(report.failureCount == 0 && !report.isCancelled ? Color.green : Color.orange)
                if let failure = report.results.first(where: { $0.status == .failed }) {
                    Text(localizedExecutionFailure(failure.message))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if let feedback = coordinator.applicationActionFeedback {
                Text(feedback)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func scanIssuesCard(_ issues: [CleanupScanIssue]) -> some View {
        DisclosureGroup(isExpanded: $showScanIssues) {
            VStack(alignment: .leading, spacing: 7) {
                Text("These locations were excluded from the cleanup totals.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(friendlyIssueMessage(issue))
                            .font(.caption2)
                        if let path = issue.path {
                            Text(abbreviated(path))
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.top, 7)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(issues.count == 1 ? "1 location could not be scanned" : "\(issues.count) locations could not be scanned")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(11)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cleanup is unavailable", systemImage: "xmark.octagon")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            Text(friendlyFailureMessage(message))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("For safety, no files are automatically removed in this state.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Try Again") { coordinator.startScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.isBusy)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var deletionScopeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            scopeRow(
                symbol: "checkmark.circle.fill",
                color: .green,
                title: "SAFE",
                text: "Included in Clean Safe Items."
            )
            scopeRow(
                symbol: "circle",
                color: .orange,
                title: "REVIEW",
                text: "Not included in Clean Safe Items. Select these individually."
            )
            scopeRow(
                symbol: "lock.fill",
                color: .secondary,
                title: "PROTECTED",
                text: "Cannot be selected or removed by MemWatch."
            )
        }
    }

    private var applicationCleanupCard: some View {
        DisclosureGroup(isExpanded: $showApplicationDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Caches for applications left open are preserved.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(coordinator.applicationCleanupPlans) { plan in
                    Toggle(isOn: Binding(
                        get: { coordinator.isApplicationCleanupEnabled(plan) },
                        set: { coordinator.setApplicationCleanupEnabled($0, for: plan) }
                    )) {
                        HStack {
                            Text(plan.name)
                                .font(.caption)
                            Spacer()
                            Text(bytes(plan.allocatedBytes))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 7) {
                Label("Applications to close during cleanup", systemImage: "app.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(coordinator.applicationCleanupPlans.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scopeRow(symbol: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryList(_ result: CleanupScanResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Found items")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !coordinator.reviewItems.isEmpty {
                    Button("Select all REVIEW items") { coordinator.selectAllReviewItems() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .disabled(!coordinator.isReady)
                }
                if !coordinator.selectedIDs.isEmpty {
                    Button("Clear selection") { coordinator.clearSelection() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .disabled(coordinator.isBusy)
                }
            }

            ForEach(nonEmptyCategories(in: result)) { category in
                categoryRow(category, result: result)
            }
        }
    }

    private func categoryRow(_ category: CleanupCategory, result: CleanupScanResult) -> some View {
        let categoryItems = items(in: category, result: result)
        let safety = categorySafetySummary(categoryItems)

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                categorySelectionControl(categoryItems, category: category)
                DisclosureGroup {
                    VStack(spacing: 6) {
                        ForEach(categoryItems) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.top, 7)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(safety.color)
                            .frame(width: 21)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if let item = categoryItems.first {
                                Text(localizedReason(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(bytes(categoryBytes(category, result: result)))
                            .font(.caption2.monospacedDigit().weight(.medium))
                        Text(safety.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(safety.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(safety.color.opacity(0.1), in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 5)
            Divider()
        }
    }

    @ViewBuilder
    private func categorySelectionControl(_ items: [CleanupCandidate], category: CleanupCategory) -> some View {
        let selectableItems = items.filter {
            !coordinator.isExcludedFromAutomaticCleanup($0) &&
                !isAutomaticSafe($0) &&
                $0.safety != .protected &&
                $0.isPotentiallyDeletable
        }

        if selectableItems.isEmpty {
            if items.contains(where: isAutomaticSafe) {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(.green)
                    .help("Safe items are included automatically")
                    .accessibilityLabel("Safe items in \(category.displayName) are included automatically")
            } else {
                Image(systemName: "lock.square.fill")
                    .foregroundStyle(.secondary)
                    .help("No selectable cleanup items in this category")
                    .accessibilityLabel("No selectable items in \(category.displayName)")
            }
        } else {
            let selectedCount = selectableItems.filter { coordinator.selectedIDs.contains($0.id) }.count
            let allSelected = selectedCount == selectableItems.count
            Button {
                if allSelected {
                    for item in selectableItems where coordinator.selectedIDs.contains(item.id) {
                        coordinator.toggleSelection(item)
                    }
                } else {
                    for item in selectableItems where !coordinator.selectedIDs.contains(item.id) {
                        coordinator.toggleSelection(item)
                    }
                }
            } label: {
                Image(systemName: selectedCount == 0 ? "square" : (allSelected ? "checkmark.square.fill" : "minus.square.fill"))
                    .foregroundStyle(selectedCount == 0 ? Color.orange : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(allSelected ? "Clear REVIEW selection in this category" : "Select REVIEW items in this category")
            .accessibilityLabel(allSelected ? "Clear selection in \(category.displayName)" : "Select items in \(category.displayName)")
            .disabled(!coordinator.isReady)
        }
    }

    private func categorySafetySummary(_ items: [CleanupCandidate]) -> (label: String, color: Color) {
        guard let first = items.first else { return ("—", .secondary) }
        if items.allSatisfy({ $0.safety == first.safety }) {
            return (first.safety.shortLabel, safetyColor(first.safety))
        }
        return ("MIXED", .orange)
    }

    @ViewBuilder
    private func selectionControl(_ item: CleanupCandidate) -> some View {
        if coordinator.isExcludedFromAutomaticCleanup(item) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .help("Cache cleanup is disabled for this application")
        } else if isAutomaticSafe(item) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .frame(width: 18, height: 18)
                .help("Automatically included in safe cleanup")
        } else if item.safety == .protected || !item.isPotentiallyDeletable {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.secondary)
                .frame(width: 18, height: 18)
                .help("Protected item; cannot be removed")
        } else {
            Button {
                coordinator.toggleSelection(item)
            } label: {
                Image(systemName: coordinator.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(safetyColor(item.safety))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(coordinator.selectedIDs.contains(item.id) ? "Remove from cleanup selection" : "Select for cleanup")
            .disabled(!coordinator.isReady)
        }
    }

    private func itemRow(_ item: CleanupCandidate) -> some View {
        HStack(alignment: .top, spacing: 9) {
            selectionControl(item)

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

                Text(localizedReason(for: item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let note = item.policyNotes.first {
                    Text(localizedPolicyNote(note))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(bytes(item.allocatedBytes))
                    .font(.caption2.monospacedDigit().weight(.semibold))

                Menu {
                    Button("Show in Finder") { coordinator.revealInFinder(item) }
                    if coordinator.canRequestApplicationClose(for: item) {
                        Divider()
                        Button("Close App and Rescan") {
                            coordinator.closeApplication(for: item)
                        }
                    }
                    Divider()
                    Button("Bu yolu yok say") { coordinator.ignorePath(for: item) }
                    if coordinator.canIgnoreProject(item) {
                        Button("Bu projeyi yok say") { coordinator.ignoreProject(for: item) }
                    }
                    if coordinator.canIgnoreApplication(item) {
                        Button("Ignore This App") { coordinator.ignoreApplication(for: item) }
                    }
                    Button("Ignore This Rule") { coordinator.ignoreRule(item) }
                    Button("Ignore This Category") { coordinator.ignoreCategory(item.category) }
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
                Label("Time Machine Snapshots", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(coordinator.snapshots.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !coordinator.preferences.cleanupEnabled {
                Text("Cleanup is off. Snapshot review and thinning are paused.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !coordinator.preferences.privilegedOperationsEnabled {
                Text("Privileged system operations are off. Snapshot review and thinning are unavailable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let error = coordinator.snapshotError {
                Text("Could not retrieve snapshots: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if coordinator.snapshots.isEmpty {
                Text(coordinator.helperService.isAvailableForCleanup ? "No local snapshots reported." : "Enable the privileged helper to review local snapshots.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Space Recovery Target", selection: $snapshotTargetBytes) {
                    Text("5 GB").tag(UInt64(5 * 1_024 * 1_024 * 1_024))
                    Text("10 GB").tag(UInt64(10 * 1_024 * 1_024 * 1_024))
                    Text("25 GB").tag(UInt64(25 * 1_024 * 1_024 * 1_024))
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button("Thin Snapshots…") { showSnapshotConfirmation = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!coordinator.isReady)
            }
        }
    }

    private var rootsCard: some View {
        DisclosureGroup(isExpanded: $showRoots) {
            VStack(alignment: .leading, spacing: 9) {
                rootList(title: "File Scan Roots", paths: coordinator.preferences.requestedRootPaths) { path in
                    coordinator.removeRequestedRoot(path)
                }
                Button("Add Scan Folder…") { coordinator.chooseRequestedRoot() }
                    .buttonStyle(.plain)
                    .font(.caption)

                Divider()

                rootList(title: "Project Roots", paths: coordinator.preferences.projectRootPaths) { path in
                    coordinator.removeProjectRoot(path)
                }
                Button("Add Project Folder…") { coordinator.chooseProjectRoot() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(.top, 9)
        } label: {
            Label("Scan Roots", systemImage: "folder.badge.gearshape")
                .font(.subheadline.weight(.semibold))
        }
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
                    Text("No ignored cleanup items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.ignoreRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.kind.displayName)
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
            Label("Ignored Items (\(coordinator.ignoreRules.count))", systemImage: "eye.slash")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Cleanup", systemImage: "clock")
                .font(.subheadline.weight(.semibold))

            if coordinator.history.isEmpty {
                Text("No cleanup history yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.history.prefix(4)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.mode == .dryRun ? "Review without removing" : (entry.outcome == .cancelled ? "Cancelled cleanup" : "Cleanup"))
                                .font(.caption.weight(.medium))
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.mode == .dryRun ? "\(entry.requestedCount) items reviewed" : "about \(bytes(entry.reclaimedBytes))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(entry.failedCount == 0 && entry.outcome != .cancelled ? Color.secondary : Color.orange)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: coordinator.preferences.cleanupEnabled ? "internaldrive" : "pause.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(coordinator.preferences.cleanupEnabled ? "No cleanup scan yet" : "Cleanup is off")
                .font(.subheadline.weight(.semibold))
            if coordinator.preferences.cleanupEnabled {
                Button("Scan Now") { coordinator.startScan() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Enable Cleanup") { coordinator.setCleanupEnabled(true) }
                    .buttonStyle(.borderedProminent)
            }
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

    private func safetyColor(_ safety: CleanupSafetyLevel) -> Color {
        switch safety {
        case .safe: return .green
        case .review: return .orange
        case .protected: return .secondary
        }
    }

    private func executionSummary(_ report: CleanupExecutionReport) -> String {
        if report.mode == .dryRun {
            return "Reviewed without removing: \(report.results.filter { $0.status == .wouldRemove }.count) confirmed, \(report.failureCount) blocked"
        }

        var parts = ["Removed \(report.successfulCount) of \(report.requestedCount) items"]
        if report.reclaimedBytes > 0 {
            parts.append("about \(bytes(report.reclaimedBytes)) reclaimed")
        }
        switch report.reclaimVerification {
        case .verified:
            if let observedDelta = report.verifiedReclaimedBytes {
                parts.append("verified free space +\(bytes(observedDelta))")
            }
        case .noNetIncrease:
            parts.append("no net increase in free space was verified")
        case .unavailable:
            parts.append("free space verification unavailable")
        case .cancelled:
            parts.append("verification cancelled")
        case .notMeasured, .notApplicable:
            break
        }
        if report.movedToTrashBytes > 0 {
            parts.append("recoverable when Trash is emptied: \(bytes(report.movedToTrashBytes))")
        }
        if report.isCancelled {
            parts.append("cancelled")
        }
        if report.failureCount > 0 {
            parts.append("\(report.failureCount) failed")
        }
        return parts.joined(separator: " · ")
    }

    private func userRelevantIssues(in issues: [CleanupScanIssue]) -> [CleanupScanIssue] {
        issues.filter {
            !$0.message.localizedCaseInsensitiveContains("coalesced")
        }
    }

    private func friendlyIssueMessage(_ issue: CleanupScanIssue) -> String {
        let message = issue.message.lowercased()
        if message.contains("not accessible") || message.contains("permission") {
            return "Could not access a folder."
        }
        if message.contains("privileged") {
            return "Could not scan a privileged system location."
        }
        if message.contains("mismatched scanner") || message.contains("unknown cleanup rule") {
            return "A result did not match the safety rules and was excluded."
        }
        return "The \(scannerName(issue.scannerID)) scan could not be completed."
    }

    private func friendlyFailureMessage(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("permission") ||
            message.localizedCaseInsensitiveContains("not accessible") {
            return "A required location could not be accessed. Check permissions and try again."
        }
        return "The scan could not be completed. Try again, and check permissions if the problem continues."
    }

    private func scannerName(_ id: CleanupScannerID) -> String {
        switch id.rawValue {
        case "user-cache": return "User Caches"
        case "user-log": return "Logs"
        case "xcode-cleanup": return "Xcode"
        case "developer-cache": return "Developer Tools"
        case "project-artifact": return "Project Artifacts"
        case "developer-build-artifact": return "Cargo Build Artifacts"
        case "ai-artifact": return "AI Data"
        case "application-leftover": return "App Leftovers"
        case "launch-item": return "Login Items"
        case "ios-backup": return "iPhone / iPad Backups"
        case "downloads": return "Downloads"
        case "trash": return "Trash"
        case "large-old-file": return "Large / Old Files"
        case "duplicate-exact": return "Duplicate Files"
        case "image-similar": return "Similar Images"
        case "mail-attachment": return "Mail Attachments"
        case "privileged-system": return "Privileged System Scan"
        default: return id.rawValue
        }
    }

    private func localizedReason(for item: CleanupCandidate) -> String {
        switch item.category {
        case .userCaches:
            return "Application cache that can be recreated when needed."
        case .systemCaches:
            return "System cache that can be recreated when safety rules allow."
        case .logs:
            return "Application logs or diagnostic data."
        case .xcode:
            if item.reason.localizedCaseInsensitiveContains("DeviceSupport") || item.displayName.localizedCaseInsensitiveContains("DeviceSupport") {
                return "Xcode device support files that can be downloaded again if needed."
            }
            if item.reason.localizedCaseInsensitiveContains("CoreSimulator") {
                return "CoreSimulator cache that requires simulator-aware maintenance."
            }
            return "Build, index, or cache data created by Xcode."
        case .developer:
            return "Cache that a developer tool can recreate or download again."
        case .projectArtifacts:
            if item.ruleID.rawValue == "project.rust.target.verified" {
                return "Recreatable Rust build output verified as part of this workspace by Cargo metadata."
            }
            return "Project dependencies, build output, or temporary files that can be recreated."
        case .aiArtifacts:
            if item.safety == .protected {
                return "Local AI model or user data; protected from automatic cleanup."
            }
            return "Cache or temporary data that an AI tool can recreate."
        case .applicationLeftovers:
            return "Data that may be left by an uninstalled app and is not in the installed app inventory."
        case .launchItems:
            return "An item that runs at startup or sign-in."
        case .iosBackups:
            return "A local iPhone or iPad backup stored on this Mac."
        case .downloads:
            return "A downloaded file, installer, or archive."
        case .trash:
            return "An item in the Trash."
        case .largeOldFiles:
            return "A large or long-unused file that needs your review."
        case .duplicates:
            return "A duplicate file with identical content."
        case .similarImages:
            return "An image that looks similar to another; never selected automatically."
        case .mailAttachments:
            return "A local copy of a mail attachment."
        case .snapshots:
            return "A local Time Machine snapshot."
        case .maintenance:
            return "Data managed by a macOS or tool maintenance operation."
        }
    }

    private func localizedPolicyNote(_ note: String) -> String {
        if note.hasPrefix("Close "), let separator = note.range(of: " before cleanup") {
            let application = String(note[note.index(note.startIndex, offsetBy: 6)..<separator.lowerBound])
            return "\(application) will be closed before its cache is cleaned."
        }
        if note == "The owning application state could not be verified; review this item before cleanup" {
            return "The app could not be verified as closed; review this item before cleanup."
        }
        if note.hasPrefix("Application: ") {
            return note
        }
        switch note {
        case "Item is newer than the automatic-cleanup age threshold":
            return "This item is newer than the automatic-cleanup age threshold."
        case "Item age could not be verified":
            return "The age of this item could not be verified."
        case "Cleanup rule explicitly protects this item":
            return "The cleanup rule explicitly protects this item."
        case "Full Disk Access is required":
            return "Full Disk Access is required."
        case "Privileged helper is required":
            return "A privileged helper is required."
        case "Target is not owned by the current user":
            return "The current user does not own this target."
        case "Cargo target verification is missing":
            return "Cargo workspace verification is missing; this target is protected."
        case "Scanner category does not match cleanup rule":
            return "The scanner category does not match the cleanup rule."
        case "Cleanup path was rejected":
            return "The cleanup path did not pass the safety check."
        case "Cleanup target no longer exists or cannot be identified":
            return "The cleanup target no longer exists or cannot be identified."
        default:
            return note
        }
    }

    private func localizedExecutionFailure(_ message: String) -> String {
        if message.contains("is still running") {
            return "The app is still running. Close it and scan again."
        }
        if message.contains("could not safely verify") {
            return "The app could not be verified as closed. Review this item before cleanup."
        }
        if message.contains("changed after scanning") {
            return "The target changed after scanning. Scan again before cleanup."
        }
        return message
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

enum WindowNavigationSelection: Equatable {
    case overview
    case cleanup
    case displays
    case settings
}

struct WindowSidebar: View {
    let selection: WindowNavigationSelection
    let onOpenOverview: () -> Void
    let onOpenCleanup: () -> Void
    let onOpenDisplays: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MemWatch").font(.subheadline.weight(.semibold))
                    Text("A cleaner, healthier Mac").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            navigationButton("Overview", symbol: "waveform.path.ecg", active: selection == .overview, action: onOpenOverview)
            navigationButton("Cleanup", symbol: "sparkles", active: selection == .cleanup, action: onOpenCleanup)
            navigationButton("Displays & Awake", symbol: "display", active: selection == .displays, action: onOpenDisplays)
            navigationButton("Settings", symbol: "gearshape", active: selection == .settings, action: onOpenSettings)

            Spacer(minLength: 16)

            Label("MemWatch Pro", systemImage: "crown.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("MemWatch Pro is not available in this build")
        }
        .padding(13)
        .frame(width: 154)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) { Divider() }
    }

    private func navigationButton(
        _ title: String,
        symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if active {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                    .padding(.horizontal, 8)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityAddTraits(.isSelected)
            } else {
                Button(action: action) {
                    Label(title, systemImage: symbol)
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                        .padding(.horizontal, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
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
        case .userCaches: return "Application Cache"
        case .systemCaches: return "System Caches"
        case .logs: return "Logs & System Files"
        case .xcode: return "Xcode"
        case .developer: return "Developer Build Files"
        case .projectArtifacts: return "Xcode / Cargo Leftovers"
        case .aiArtifacts: return "AI & Local Model Data"
        case .applicationLeftovers: return "App Leftovers"
        case .launchItems: return "Login Items"
        case .iosBackups: return "iPhone / iPad Backups"
        case .downloads: return "Downloads & Installers"
        case .trash: return "Trash"
        case .largeOldFiles: return "Large Files"
        case .duplicates: return "Duplicate Files"
        case .similarImages: return "Similar Images"
        case .mailAttachments: return "Mail Attachments"
        case .snapshots: return "Time Machine Snapshots"
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

private extension CleanupIgnoreKind {
    var displayName: String {
        switch self {
        case .path: return "Path"
        case .project: return "Project"
        case .application: return "Application"
        case .rule: return "Rule"
        case .category: return "Category"
        case .scanner: return "Scanner"
        }
    }
}
