import SwiftUI

struct CleanupView: View {
    @ObservedObject var coordinator: CleanupCoordinator

    @State private var showSafeConfirmation = false
    @State private var showSelectedConfirmation = false
    @State private var showSnapshotConfirmation = false
    @State private var snapshotTargetBytes: UInt64 = 10 * 1_024 * 1_024 * 1_024
    @State private var showIgnoredItems = false
    @State private var showRoots = false
    @State private var showItemDetails = false
    @State private var showAdvancedDetails = false
    @State private var showScanIssues = false
    @State private var showApplicationDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if coordinator.phase == .scanning {
                    progressCard
                }

                if case .failed(let message) = coordinator.phase {
                    failureCard(message)
                }

                if let result = coordinator.scanResult {
                    summaryCard(result)
                    if !result.items.isEmpty {
                        itemReviewSection(result)
                    }
                    let relevantIssues = userRelevantIssues(in: result.issues)
                    if !relevantIssues.isEmpty {
                        scanIssuesCard(relevantIssues)
                    }
                } else if coordinator.phase != .scanning,
                          !isFailedPhase {
                    emptyState
                }

                if needsPermissionAttention {
                    permissionNotice
                }
                advancedDetails
            }
            .padding(16)
        }
        .onAppear {
            showItemDetails = false
            showAdvancedDetails = false
            showScanIssues = false
            showApplicationDetails = false
            if coordinator.scanResult == nil, !coordinator.isBusy {
                coordinator.startScan()
            }
        }
        .confirmationDialog(
            "Yalnızca güvenli öğeler temizlensin mi?",
            isPresented: $showSafeConfirmation,
            titleVisibility: .visible
        ) {
            Button("\(bytes(coordinator.automaticSafeBytes)) Güvenli Temizle") {
                coordinator.cleanSafeItemsConfirmed()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yalnızca GÜVENLİ olarak sınıflandırılan ve ayrıca açık onay gerektirmeyen öğeler kaldırılır. İNCELE ve KORUNAN öğeler bu işlemde silinmez. Her hedef silinmeden hemen önce yeniden doğrulanır.")
        }
        .confirmationDialog(
            "Seçilen öğeler temizlensin mi?",
            isPresented: $showSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button("\(bytes(coordinator.selectedBytes)) Seçili Öğeyi Temizle") {
                coordinator.cleanSelectedConfirmed()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Seçtiğin İNCELE öğeleri proje bağımlılıkları, yedekler, indirilenler veya yeniden oluşturma/kurtarma maliyeti olan başka veriler içerebilir. Yalnızca seçili öğeler işleme alınır.")
        }
        .confirmationDialog(
            "Time Machine anlık görüntüleri inceltilsin mi?",
            isPresented: $showSnapshotConfirmation,
            titleVisibility: .visible
        ) {
            Button("\(bytes(snapshotTargetBytes)) Alan İste") {
                coordinator.thinTimeMachineSnapshots(targetBytes: snapshotTargetBytes)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("MemWatch, istenen alanı geri kazanmak için tmutil kullanır. APFS anlık görüntü dosyalarını doğrudan silmez veya değiştirmez.")
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
            Label("Derin Temizleme", systemImage: "sparkles")
                .font(.headline)
            Spacer()
            if coordinator.isBusy {
                Button("İptal") { coordinator.cancelCurrentOperation() }
                    .buttonStyle(.plain)
                    .font(.caption)
            } else {
                Button {
                    coordinator.startScan()
                } label: {
                    Label("Yeniden tara", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Yeniden tara")
                .accessibilityLabel("Yeniden tara")
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
            Text("Temizleme seçenekleri")
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
                "Yetkili sistem işlemleri",
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
                "Özel uyumluluk yöntemleri",
                isOn: Binding(
                    get: { coordinator.preferences.privateBackendEnabled },
                    set: { coordinator.setPrivateBackendEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption.weight(.semibold))
            .disabled(!coordinator.preferences.cleanupEnabled)

            Text("Özel uyumluluk yöntemleri belgelenmemiş macOS davranışlarına dayanabilir.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            capabilityRow(
                symbol: "lock.shield",
                title: "Yetkili yardımcı",
                value: helperLabel,
                good: coordinator.helperService.isAvailableForCleanup
            )

            if coordinator.helperService.isRegistering {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yetkili yardımcı kuruluyor…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if coordinator.helperService.state == .requiresApproval {
                Button("Sistem Ayarlarında Onayla") {
                    coordinator.openHelperApprovalSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if !coordinator.helperService.isAvailableForCleanup {
                Button(coordinator.helperService.state == .enabled ? "Bağlantıyı Yeniden Dene" : "Derin Sistem Temizlemeyi Etkinleştir") {
                    coordinator.registerHelper()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!coordinator.preferences.cleanupEnabled || !coordinator.preferences.privilegedOperationsEnabled)
            } else {
                Button("Yetkili Yardımcıyı Devre Dışı Bırak") {
                    coordinator.unregisterHelper()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let helperError = coordinator.helperService.lastError,
               !helperError.isEmpty {
                Text("Yetkili yardımcı etkinleştirilemedi. Yeniden deneyin veya Sistem Ayarları'nı kontrol edin.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            capabilityRow(
                symbol: "externaldrive.badge.checkmark",
                title: "Tam Disk Erişimi",
                value: fullDiskAccessLabel,
                good: coordinator.fullDiskAccessService.isAvailable
            )

            if !coordinator.fullDiskAccessService.isAvailable {
                Button("Tam Disk Erişimi Ayarlarını Aç") {
                    coordinator.openFullDiskAccessSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("İzinleri yeniden denetle") {
                coordinator.refreshPermissionsAndHelper()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var storageIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("APFS depolama", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))

            if let capacity = coordinator.storageSpaceIntelligence {
                capacityRow("Şu an boş", value: capacity.immediateAvailableBytes)
                capacityRow("macOS gerektiğinde boşaltabilir", value: capacity.purgeableEstimateBytes)
                capacityRow("Toplam kullanılabilir", value: capacity.importantUsageAvailableBytes)
                Text("macOS'un yönettiği alan temizlik toplamına eklenmez.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Başlangıç diski için APFS kapasite ayrıntıları alınamadı.")
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
        if coordinator.helperService.isRegistering { return "Kuruluyor…" }

        switch coordinator.helperService.state {
        case .enabled:
            return coordinator.helperService.connectionVerified ? "Etkin" : "Bağlantı doğrulanamadı"
        case .notRegistered: return "Yüklü değil"
        case .requiresApproval: return "Onay gerekiyor"
        case .notFound: return "Bulunamadı"
        case .unavailable: return "Kullanılamıyor"
        case .installing: return "Kuruluyor…"
        }
    }

    private var fullDiskAccessLabel: String {
        switch coordinator.fullDiskAccessService.state {
        case .granted: return "Verildi"
        case .denied: return "Verilmedi"
        case .unknown: return "Bilinmiyor"
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bazı sistem alanları taranamayabilir", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Mevcut sonuçları temizleyebilirsin. Daha kapsamlı bir tarama için eksik izni tamamla.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if coordinator.helperService.isRegistering {
                    ProgressView()
                        .controlSize(.small)
                    Text("Yetkili yardımcı etkinleştiriliyor…")
                        .font(.caption2)
                } else if coordinator.helperService.state == .requiresApproval {
                    Button("Yardımcıyı onayla") { coordinator.openHelperApprovalSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if !coordinator.helperService.isAvailableForCleanup {
                    Button("Sistem taramasını etkinleştir") { coordinator.registerHelper() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if !coordinator.fullDiskAccessService.isAvailable {
                    Button("Disk erişimi ver") { coordinator.openFullDiskAccessSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()
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
            Label("Ayarlar ve ayrıntılar", systemImage: "slider.horizontal.3")
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
                Text("Taranıyor…")
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
            return "Hazırlanıyor"
        case .scanning(_, let completed, let total):
            return "Dosyalar kontrol ediliyor · \(completed + 1) / \(max(total, 1))"
        case .evaluating(_, let candidateCount):
            return "\(candidateCount) öğe güvenlik açısından değerlendiriliyor"
        case .finishing:
            return "Son kontroller yapılıyor"
        }
    }

    private func summaryCard(_: CleanupScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bytes(coordinator.automaticSafeBytes))
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(coordinator.automaticSafeBytes > 0 ? Color.primary : Color.secondary)
                Text("güvenle temizlenebilir")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("Yalnızca yeniden oluşturulabilen ve silinmeden önce tekrar doğrulanan öğeler temizlenir.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !coordinator.applicationCleanupPlans.isEmpty {
                Divider()
                applicationCleanupCard
            }

            primaryActions
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Güvenli temizlik özeti")
    }

    private func scanIssuesCard(_ issues: [CleanupScanIssue]) -> some View {
        DisclosureGroup(isExpanded: $showScanIssues) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Bu konumlar temizlik hesabına katılmadı.")
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
                Text(issues.count == 1 ? "1 konum taranamadı" : "\(issues.count) konum taranamadı")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(11)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Temizleme kullanılamıyor", systemImage: "xmark.octagon")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            Text(friendlyFailureMessage(message))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Güvenlik için bu durumda hiçbir dosya otomatik olarak silinmez.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Yeniden dene") { coordinator.startScan() }
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
            Label("Ne silinecek?", systemImage: "checklist")
                .font(.caption.weight(.semibold))

            scopeRow(
                symbol: "checkmark.circle.fill",
                color: .green,
                title: "GÜVENLİ",
                text: "Ana “Güvenli Temizle” düğmesine otomatik dahildir."
            )
            scopeRow(
                symbol: "circle",
                color: .orange,
                title: "İNCELE",
                text: "Ana düğme bunları silmez. Önce turuncu daireden seçmen gerekir."
            )
            scopeRow(
                symbol: "lock.fill",
                color: .secondary,
                title: "KORUNAN",
                text: "Seçilemez ve MemWatch tarafından temizlenmez."
            )
        }
    }

    private var applicationCleanupCard: some View {
        DisclosureGroup(isExpanded: $showApplicationDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Açık bıraktığın uygulamanın önbelleği korunur.")
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
                Label("Temizlik sırasında kapatılacak uygulamalar", systemImage: "app.badge.checkmark")
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

    private var primaryActions: some View {
        VStack(spacing: 8) {
            Button {
                showSafeConfirmation = true
            } label: {
                Label("Güvenli \(bytes(coordinator.automaticSafeBytes)) Temizle", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(coordinator.automaticSafeBytes == 0 || !coordinator.isReady)

            Button("Önce Silmeden Kontrol Et") { coordinator.dryRunSafeItems() }
                .buttonStyle(.plain)
                .font(.caption)
                .disabled(coordinator.automaticSafeBytes == 0 || !coordinator.isReady)

            if let report = coordinator.lastExecution {
                HStack {
                    Image(systemName: report.failureCount == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(executionSummary(report))
                        .lineLimit(2)
                    Spacer()
                }
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
    }

    private func itemReviewSection(_ result: CleanupScanResult) -> some View {
        DisclosureGroup(isExpanded: $showItemDetails) {
            VStack(alignment: .leading, spacing: 12) {
                deletionScopeCard
                Divider()
                categoryList(result)

                if !coordinator.selectedIDs.isEmpty {
                    Divider()
                    selectedItemActions
                }
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.reviewBytes > 0 ? "Daha fazla alan aç" : "Temizlik ayrıntılarını gör")
                    .font(.subheadline.weight(.semibold))
                if result.reviewBytes > 0 {
                    Text("\(bytes(result.reviewBytes)) için öğeleri tek tek seçmen gerekir")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var selectedItemActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(coordinator.selectedIDs.count) öğe seçili · \(bytes(coordinator.selectedBytes))")
                .font(.caption.monospacedDigit().weight(.semibold))

            HStack(spacing: 8) {
                Button("Silmeden Kontrol Et") { coordinator.dryRunSelected() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(!coordinator.isReady)
                Button("Seçilenleri Temizle") { showSelectedConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!coordinator.isReady)
            }
            .controlSize(.small)
        }
    }

    private func categoryList(_ result: CleanupScanResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Bulunan öğeler")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !coordinator.reviewItems.isEmpty {
                    Button("Tüm İNCELE öğelerini seç") { coordinator.selectAllReviewItems() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                }
                if !coordinator.selectedIDs.isEmpty {
                    Button("Seçimi temizle") { coordinator.clearSelection() }
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
                .padding(.vertical, 5)
                Divider()
            }
        }
    }

    @ViewBuilder
    private func selectionControl(_ item: CleanupCandidate) -> some View {
        if coordinator.isExcludedFromAutomaticCleanup(item) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .help("Bu uygulama için cache temizleme kapalı")
        } else if isAutomaticSafe(item) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .frame(width: 18, height: 18)
                .help("Güvenli temizlemeye otomatik dahil")
        } else if item.safety == .protected || !item.isPotentiallyDeletable {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.secondary)
                .frame(width: 18, height: 18)
                .help("Korunan öğe; temizlenmez")
        } else {
            Button {
                coordinator.toggleSelection(item)
            } label: {
                Image(systemName: coordinator.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(safetyColor(item.safety))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(coordinator.selectedIDs.contains(item.id) ? "Temizleme seçiminden çıkar" : "Temizlemek için seç")
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
                    Button("Finder'da Göster") { coordinator.revealInFinder(item) }
                    if coordinator.canRequestApplicationClose(for: item) {
                        Divider()
                        Button("Uygulamayı kapat ve yeniden tara") {
                            coordinator.closeApplication(for: item)
                        }
                    }
                    Divider()
                    Button("Bu yolu yok say") { coordinator.ignorePath(for: item) }
                    if coordinator.canIgnoreProject(item) {
                        Button("Bu projeyi yok say") { coordinator.ignoreProject(for: item) }
                    }
                    if coordinator.canIgnoreApplication(item) {
                        Button("Bu uygulamayı yok say") { coordinator.ignoreApplication(for: item) }
                    }
                    Button("Bu kuralı yok say") { coordinator.ignoreRule(item) }
                    Button("Bu kategoriyi yok say") { coordinator.ignoreCategory(item.category) }
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
                Label("Time Machine anlık görüntüleri", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(coordinator.snapshots.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !coordinator.preferences.cleanupEnabled {
                Text("Temizleme kapalı. Anlık görüntü inceleme ve inceltme duraklatıldı.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !coordinator.preferences.privilegedOperationsEnabled {
                Text("Yetkili sistem işlemleri kapalı. Anlık görüntü inceleme ve inceltme kapsam dışında.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let error = coordinator.snapshotError {
                Text("Anlık görüntüler alınamadı: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if coordinator.snapshots.isEmpty {
                Text(coordinator.helperService.isAvailableForCleanup ? "Yerel anlık görüntü bildirilmedi." : "Yerel anlık görüntüleri incelemek için yetkili yardımcıyı etkinleştir.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Geri kazanma hedefi", selection: $snapshotTargetBytes) {
                    Text("5 GB").tag(UInt64(5 * 1_024 * 1_024 * 1_024))
                    Text("10 GB").tag(UInt64(10 * 1_024 * 1_024 * 1_024))
                    Text("25 GB").tag(UInt64(25 * 1_024 * 1_024 * 1_024))
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button("Anlık görüntüleri incelt…") { showSnapshotConfirmation = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!coordinator.isReady)
            }
        }
    }

    private var rootsCard: some View {
        DisclosureGroup(isExpanded: $showRoots) {
            VStack(alignment: .leading, spacing: 9) {
                rootList(title: "Dosya tarama kökleri", paths: coordinator.preferences.requestedRootPaths) { path in
                    coordinator.removeRequestedRoot(path)
                }
                Button("Tarama klasörü ekle…") { coordinator.chooseRequestedRoot() }
                    .buttonStyle(.plain)
                    .font(.caption)

                Divider()

                rootList(title: "Proje kökleri", paths: coordinator.preferences.projectRootPaths) { path in
                    coordinator.removeProjectRoot(path)
                }
                Button("Proje klasörü ekle…") { coordinator.chooseProjectRoot() }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
            .padding(.top, 9)
        } label: {
            Label("Tarama kökleri", systemImage: "folder.badge.gearshape")
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
                    Text("Yok sayılan temizleme öğesi yok")
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
            Label("Yok sayılan öğeler (\(coordinator.ignoreRules.count))", systemImage: "eye.slash")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Son temizlemeler", systemImage: "clock")
                .font(.subheadline.weight(.semibold))

            if coordinator.history.isEmpty {
                Text("Henüz temizleme geçmişi yok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.history.prefix(4)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.mode == .dryRun ? "Silmeden kontrol" : (entry.outcome == .cancelled ? "İptal edilen temizleme" : "Temizleme"))
                                .font(.caption.weight(.medium))
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.mode == .dryRun ? "\(entry.requestedCount) öğe denetlendi" : "tahmini \(bytes(entry.reclaimedBytes))")
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
            Text(coordinator.preferences.cleanupEnabled ? "Henüz temizleme taraması yapılmadı" : "Temizleme kapalı")
                .font(.subheadline.weight(.semibold))
            if coordinator.preferences.cleanupEnabled {
                Button("Şimdi Tara") { coordinator.startScan() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Temizlemeyi Etkinleştir") { coordinator.setCleanupEnabled(true) }
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
            return "Silmeden kontrol: \(report.results.filter { $0.status == .wouldRemove }.count) doğrulandı, \(report.failureCount) engellendi"
        }

        var parts = ["\(report.successfulCount)/\(report.requestedCount) öğe kaldırıldı"]
        if report.reclaimedBytes > 0 {
            parts.append("tahmini \(bytes(report.reclaimedBytes)) dosya alanı")
        }
        switch report.reclaimVerification {
        case .verified:
            if let observedDelta = report.verifiedReclaimedBytes {
                parts.append("doğrulanan boş alan +\(bytes(observedDelta))")
            }
        case .noNetIncrease:
            parts.append("net boş alan artışı doğrulanamadı")
        case .unavailable:
            parts.append("boş alan doğrulaması kullanılamadı")
        case .cancelled:
            parts.append("doğrulama iptal edildi")
        case .notMeasured, .notApplicable:
            break
        }
        if report.movedToTrashBytes > 0 {
            parts.append("Çöp Kutusu boşaltılınca geri kazanılır: \(bytes(report.movedToTrashBytes))")
        }
        if report.isCancelled {
            parts.append("iptal edildi")
        }
        if report.failureCount > 0 {
            parts.append("\(report.failureCount) başarısız")
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
            return "Klasöre erişilemedi."
        }
        if message.contains("privileged") {
            return "Yetkili sistem alanı taranamadı."
        }
        if message.contains("mismatched scanner") || message.contains("unknown cleanup rule") {
            return "Bir sonuç güvenlik kurallarıyla eşleşmedi ve hesaba katılmadı."
        }
        return "\(scannerName(issue.scannerID)) taraması tamamlanamadı."
    }

    private func friendlyFailureMessage(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("permission") ||
            message.localizedCaseInsensitiveContains("not accessible") {
            return "Gerekli bir konuma erişilemedi. İzinleri kontrol edip yeniden deneyin."
        }
        return "Tarama tamamlanamadı. Yeniden deneyin; sorun sürerse izinleri kontrol edin."
    }

    private func scannerName(_ id: CleanupScannerID) -> String {
        switch id.rawValue {
        case "user-cache": return "Kullanıcı önbellekleri"
        case "user-log": return "Günlükler"
        case "xcode-cleanup": return "Xcode"
        case "developer-cache": return "Geliştirici araçları"
        case "project-artifact": return "Proje artıkları"
        case "developer-build-artifact": return "Cargo derleme artıkları"
        case "ai-artifact": return "Yapay zekâ verileri"
        case "application-leftover": return "Uygulama artıkları"
        case "launch-item": return "Başlangıç öğeleri"
        case "ios-backup": return "iPhone / iPad yedekleri"
        case "downloads": return "İndirilenler"
        case "trash": return "Çöp Kutusu"
        case "large-old-file": return "Büyük / eski dosyalar"
        case "duplicate-exact": return "Yinelenen dosyalar"
        case "image-similar": return "Benzer görseller"
        case "mail-attachment": return "Posta ekleri"
        case "privileged-system": return "Yetkili sistem taraması"
        default: return id.rawValue
        }
    }

    private func localizedReason(for item: CleanupCandidate) -> String {
        switch item.category {
        case .userCaches:
            return "Uygulama önbelleği; gerektiğinde uygulama tarafından yeniden oluşturulabilir."
        case .systemCaches:
            return "Sistem önbelleği; güvenlik kuralları izin verdiğinde yeniden oluşturulabilir veri."
        case .logs:
            return "Uygulama günlüğü veya tanılama verisi."
        case .xcode:
            if item.reason.localizedCaseInsensitiveContains("DeviceSupport") || item.displayName.localizedCaseInsensitiveContains("DeviceSupport") {
                return "Xcode cihaz sürümü destek dosyaları; gerekirse yeniden indirilebilir."
            }
            if item.reason.localizedCaseInsensitiveContains("CoreSimulator") {
                return "CoreSimulator önbelleği; simülatör farkındalıklı bakım gerektirir."
            }
            return "Xcode tarafından üretilmiş derleme, dizin veya önbellek verisi."
        case .developer:
            return "Geliştirici aracının yeniden oluşturabileceği veya yeniden indirebileceği önbellek."
        case .projectArtifacts:
            if item.ruleID.rawValue == "project.rust.target.verified" {
                return "Cargo metadata ile workspace'e ait olduğu doğrulanan, yeniden üretilebilir Rust derleme çıktısı."
            }
            return "Projede yeniden oluşturulabilen bağımlılık, derleme çıktısı veya geçici dosya."
        case .aiArtifacts:
            if item.safety == .protected {
                return "Yerel yapay zekâ modeli veya kullanıcı açısından değerli veri; otomatik temizlenmez."
            }
            return "Yapay zekâ aracının yeniden oluşturabileceği önbellek veya geçici veri."
        case .applicationLeftovers:
            return "Yüklü uygulama envanteriyle eşleşmeyen, kaldırılmış uygulamadan kalmış olabilecek veri."
        case .launchItems:
            return "Başlangıçta veya oturum açıldığında çalışan öğe."
        case .iosBackups:
            return "Bu Mac'te saklanan yerel iPhone veya iPad yedeği."
        case .downloads:
            return "İndirilen dosya, kurulum paketi veya arşiv."
        case .trash:
            return "Çöp Kutusu'nda bulunan öğe."
        case .largeOldFiles:
            return "Büyük veya uzun süredir kullanılmayan dosya; kullanıcı kararı gerekir."
        case .duplicates:
            return "İçeriği birebir aynı olduğu doğrulanan yinelenen dosya."
        case .similarImages:
            return "Görsel olarak benzer bulunan resim; otomatik seçim yapılmaz."
        case .mailAttachments:
            return "Posta uygulamasının yerel ek kopyası."
        case .snapshots:
            return "Yerel Time Machine anlık görüntüsü."
        case .maintenance:
            return "macOS veya bir aracın bakım işlemiyle yönetilmesi gereken veri."
        }
    }

    private func localizedPolicyNote(_ note: String) -> String {
        if note.hasPrefix("Close "), let separator = note.range(of: " before cleanup") {
            let application = String(note[note.index(note.startIndex, offsetBy: 6)..<separator.lowerBound])
            return "\(application) temizleme başlamadan önce kapatılacak; cache'i temizlenecek."
        }
        if note == "The owning application state could not be verified; review this item before cleanup" {
            return "İlgili uygulamanın kapalı olduğu doğrulanamadı; bu öğeyi temizlemeden önce inceleyin."
        }
        if note.hasPrefix("Application: ") {
            return note
        }
        switch note {
        case "Item is newer than the automatic-cleanup age threshold":
            return "Öğe, otomatik temizleme için belirlenen yaş sınırından daha yeni."
        case "Item age could not be verified":
            return "Öğenin yaşı doğrulanamadı."
        case "Cleanup rule explicitly protects this item":
            return "Temizleme kuralı bu öğeyi özellikle koruyor."
        case "Full Disk Access is required":
            return "Tam Disk Erişimi gerekli."
        case "Privileged helper is required":
            return "Yetkili yardımcı gerekli."
        case "Target is not owned by the current user":
            return "Hedef dosyanın sahibi mevcut kullanıcı değil."
        case "Cargo target verification is missing":
            return "Cargo workspace doğrulaması bulunamadı; hedef korunuyor."
        case "Scanner category does not match cleanup rule":
            return "Tarayıcı kategorisi temizleme kuralıyla eşleşmiyor."
        case "Cleanup path was rejected":
            return "Temizleme yolu güvenlik denetiminden geçmedi."
        case "Cleanup target no longer exists or cannot be identified":
            return "Temizleme hedefi artık yok veya kimliği doğrulanamıyor."
        default:
            return note
        }
    }

    private func localizedExecutionFailure(_ message: String) -> String {
        if message.contains("is still running") {
            return "İlgili uygulama çalışıyor; uygulamayı kapatıp yeniden tarayın."
        }
        if message.contains("could not safely verify") {
            return "İlgili uygulamanın kapalı olduğu doğrulanamadı; öğeyi inceleyerek temizleyin."
        }
        if message.contains("changed after scanning") {
            return "Hedef taramadan sonra değişti; yeniden tarayın."
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

private extension CleanupSafetyLevel {
    var shortLabel: String {
        switch self {
        case .safe: return "GÜVENLİ"
        case .review: return "İNCELE"
        case .protected: return "KORUNAN"
        }
    }
}

private extension CleanupCategory {
    var displayName: String {
        switch self {
        case .userCaches: return "Kullanıcı Önbellekleri"
        case .systemCaches: return "Sistem Önbellekleri"
        case .logs: return "Günlükler ve Tanılama"
        case .xcode: return "Xcode"
        case .developer: return "Geliştirici Araçları"
        case .projectArtifacts: return "Proje Artıkları"
        case .aiArtifacts: return "Yapay Zekâ ve Yerel Modeller"
        case .applicationLeftovers: return "Uygulama Artıkları"
        case .launchItems: return "Başlangıç Öğeleri"
        case .iosBackups: return "iPhone / iPad Yedekleri"
        case .downloads: return "İndirilenler ve Kurulum Dosyaları"
        case .trash: return "Çöp Kutusu"
        case .largeOldFiles: return "Büyük ve Eski Dosyalar"
        case .duplicates: return "Birebir Yinelenen Dosyalar"
        case .similarImages: return "Benzer Görseller"
        case .mailAttachments: return "Posta Ekleri"
        case .snapshots: return "Anlık Görüntüler"
        case .maintenance: return "Bakım"
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
        case .path: return "Yol"
        case .project: return "Proje"
        case .application: return "Uygulama"
        case .rule: return "Kural"
        case .category: return "Kategori"
        case .scanner: return "Tarayıcı"
        }
    }
}
