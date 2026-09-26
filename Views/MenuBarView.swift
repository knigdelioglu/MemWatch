import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MonitoringService
    var windowLayout = false
    @State private var route: PanelRoute = .dashboard

    private enum PanelRoute: Equatable {
        case dashboard
        case memory
        case storage
        case energy
        case system
    }

    private var snapshot: MemorySnapshot { monitor.snapshot }
    private var intelligence: SwapIntelligenceResult { monitor.intelligence }
    private var pressureEstimate: MemoryPressureEstimate { monitor.memoryPressureEstimate }

    var body: some View {
        ZStack {
            switch route {
            case .dashboard:
                dashboardView
                    .transition(.opacity)
            case .memory:
                detailContainer(title: "Memory", symbol: "memorychip") {
                    memoryDetailView
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .storage:
                detailContainer(title: "Storage", symbol: "internaldrive") {
                    storageDetailView
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .energy:
                detailContainer(title: "Energy", symbol: "bolt.fill") {
                    energyDetailView
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .system:
                detailContainer(title: "System", symbol: "gauge.with.dots.needle.50percent") {
                    systemDetailView
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: windowLayout ? nil : 390, height: windowLayout ? nil : 860)
        .frame(maxWidth: windowLayout ? .infinity : nil, maxHeight: windowLayout ? .infinity : nil)
        .animation(.easeInOut(duration: 0.16), value: route)
        .onAppear {
            route = .dashboard
        }
    }

    private var dashboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                dashboardHeader

                moduleCard(
                    route: .memory,
                    title: "Memory",
                    symbol: "memorychip",
                    value: "\(shortBytes(snapshot.usedBytes)) of \(shortBytes(snapshot.totalBytes))",
                    detail: "\(snapshot.usagePercent)% used · \(monitor.pressure.displayName) pressure · Swap \(shortBytes(snapshot.swapUsedBytes))",
                    accent: pressureColor,
                    progress: Double(snapshot.usagePercent) / 100
                )

                moduleCard(
                    route: .system,
                    title: "CPU & System",
                    symbol: "cpu",
                    value: systemHeadline,
                    detail: "Thermal state · \(monitor.diagnostics.thermalState.displayName)",
                    accent: thermalColor,
                    progress: monitor.diagnostics.cpuUsagePercent.map { $0 / 100 }
                )

                moduleCard(
                    route: .storage,
                    title: "Storage",
                    symbol: "internaldrive",
                    value: storageHeadline,
                    detail: storageDetail,
                    accent: storageDashboardColor,
                    progress: internalVolume.map { Double($0.usagePercent) / 100 }
                )

                moduleCard(
                    route: .energy,
                    title: "Power",
                    symbol: powerSymbol,
                    value: energyHeadline,
                    detail: "\(monitor.powerSnapshot.flow.displayName) · \(monitor.powerSnapshot.systemLoadWatts.map { String(format: "%.1f W", $0) } ?? "Power telemetry unavailable")",
                    accent: energyColor
                )

                notificationDashboardCard

                HStack {
                    Label(headerSummary, systemImage: statusSymbol)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)

                    Spacer()

                    Button("Refresh") {
                        monitor.refresh(forceStorage: true, forceDiagnostics: true)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.top, 2)
            }
            .padding(12)
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 31, height: 31)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("MemWatch").font(.headline)
                Text("A cleaner, healthier Mac").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Label(healthName == "Good" ? "All Systems Good" : healthName, systemImage: statusSymbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(healthColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(healthColor.opacity(0.1), in: Capsule())
        }
    }

    private func moduleCard(
        route destination: PanelRoute,
        title: String,
        symbol: String,
        value: String,
        detail: String,
        accent: Color,
        progress: Double? = nil
    ) -> some View {
        Button {
            route = destination
        } label: {
            HStack(alignment: .top, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(value)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if let progress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(accent)
                            .controlSize(.small)
                    }
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var notificationDashboardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Smart Alerts", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { monitor.notificationsEnabled },
                        set: { monitor.setNotificationsEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("System permission")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(monitor.notificationAuthorization.displayName)
                    .foregroundStyle(notificationPermissionColor)
            }
            .font(.caption)

            ForEach(activeAlertSummaries, id: \.self) { alert in
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if activeAlertSummaries.isEmpty {
                Label("No current system alerts", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if monitor.notificationAuthorization == .denied {
                Button("Open Notification Settings") {
                    monitor.openNotificationSettings()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var activeAlertSummaries: [String] {
        var alerts: [String] = []
        if monitor.pressure != .normal { alerts.append("Memory pressure is \(monitor.pressure.displayName.lowercased())") }
        if intelligence.state == .activeSwap || intelligence.state == .pressure || intelligence.state == .critical {
            alerts.append("Active swap usage (\(shortBytes(snapshot.swapUsedBytes)))")
        }
        if let volume = monitor.storageVolumes.first(where: { $0.health == .warning || $0.health == .critical }) {
            alerts.append("\(volume.name) storage is almost full")
        }
        if monitor.diagnostics.thermalState == .serious || monitor.diagnostics.thermalState == .critical {
            alerts.append("System is running hot")
        }
        return alerts
    }

    private func detailContainer<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    route = .dashboard
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 72, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
                .help("Back to dashboard")

                Label(title, systemImage: symbol)
                    .font(.headline)

                Spacer()

                Button {
                    monitor.refresh(forceStorage: true, forceDiagnostics: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()

            content()
        }
    }

    private var memoryDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory Used")
                        .font(.subheadline.weight(.semibold))
                    Text("\(bytes(snapshot.usedBytes)) / \(bytes(snapshot.totalBytes)) · \(snapshot.usagePercent)%")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("Available headroom: \(bytes(snapshot.availableBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    MemoryDonutChart(snapshot: snapshot)
                        .frame(width: 190, height: 190)

                    VStack(alignment: .leading, spacing: 10) {
                        memoryLegend("App Memory", bytes: snapshot.appMemoryBytes, color: .cyan)
                        memoryLegend("Wired", bytes: snapshot.wiredBytes, color: .blue)
                        memoryLegend("Compressed", bytes: snapshot.compressedBytes, color: .indigo)
                        memoryLegend("Cached Files", bytes: snapshot.cachedFilesBytes, color: .purple)
                        Text("Cached Files is reclaimable and separate from Memory Used.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 10) {
                    memoryInfoCard(
                        title: "Pressure Estimate",
                        value: "\(pressureEstimate.percent)%",
                        subtitle: monitor.pressure.displayName,
                        explanation: pressureExplanation,
                        color: pressureColor
                    )

                    memoryInfoCard(
                        title: "Swap File",
                        value: shortBytes(snapshot.swapUsedBytes),
                        subtitle: intelligence.state.displayName,
                        explanation: swapExplanation,
                        color: statusColor
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top Memory Users")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Refresh") {
                            monitor.refresh(forceDiagnostics: true)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }

                    Text("App helpers are grouped; standalone system and CLI processes remain visible.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if monitor.diagnostics.topProcesses.isEmpty {
                        Text("No process memory snapshot available yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.diagnostics.topProcesses.prefix(7)) { process in
                            HStack(spacing: 9) {
                                Image(systemName: process.groupKind.symbolName)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(process.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(process.memoryMetric.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(bytes(process.memoryBytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
        }
    }

    private func memoryLegend(_ title: String, bytes value: UInt64, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(bytes(value))
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
        }
    }

    private func memoryInfoCard(
        title: String,
        value: String,
        subtitle: String,
        explanation: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            }

            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)

            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var storageDetailView: some View {
        ScrollView {
            storageSection
                .padding(16)
        }
    }

    private var energyDetailView: some View {
        ScrollView {
            PowerMonitorView(
                snapshot: monitor.powerSnapshot,
                history: monitor.powerHistory,
                averageWatts: monitor.averageObservablePowerWatts
            )
            .padding(16)
        }
    }

    private var systemDetailView: some View {
        ScrollView {
            SystemDiagnosticsView(
                diagnostics: monitor.diagnostics,
                history: monitor.systemHistory,
                launchAtLoginState: monitor.launchAtLoginState,
                launchAtLoginError: monitor.launchAtLoginError,
                onLaunchAtLoginChange: { monitor.setLaunchAtLogin($0) },
                onOpenLoginItemsSettings: { monitor.openLoginItemsSettings() },
                onRefreshProcesses: { monitor.refresh(forceDiagnostics: true) }
            )
            .padding(16)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Storage")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(monitor.storageVolumes.count) volume\(monitor.storageVolumes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if monitor.storageVolumes.isEmpty {
                Text("No local storage volumes detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitor.storageVolumes) { volume in
                    storageVolumeRow(volume)
                    if volume.id != monitor.storageVolumes.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func storageVolumeRow(_ volume: StorageVolumeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                    .foregroundStyle(storageColor(volume.health))

                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(volume.isInternal ? "Internal" : "External")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(volume.usagePercent)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: volume.usageRatio)
                .tint(storageColor(volume.health))

            HStack {
                Text("\(fileBytes(volume.usedBytes)) used")
                Spacer()
                Text("\(fileBytes(volume.availableBytes)) free of \(fileBytes(volume.totalBytes))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var internalVolume: StorageVolumeSnapshot? {
        monitor.storageVolumes.first(where: { $0.isInternal })
    }

    private var storageHeadline: String {
        guard let internalVolume else { return "Unavailable" }
        return "\(fileBytes(internalVolume.availableBytes)) free"
    }

    private var storageDetail: String {
        guard let internalVolume else { return "No internal volume detected" }
        return "\(internalVolume.usagePercent)% used · \(internalVolume.health.displayName)"
    }

    private var storageDashboardColor: Color {
        guard let internalVolume else { return .secondary }
        return storageColor(internalVolume.health)
    }

    private var energyHeadline: String {
        if let percent = monitor.powerSnapshot.batteryPercentClamped {
            return "Battery \(percent)%"
        }
        return monitor.powerSnapshot.source.displayName
    }

    private var energyColor: Color {
        switch monitor.powerSnapshot.flow {
        case .charging: return .green
        case .discharging: return .orange
        case .idle: return .blue
        case .unavailable: return .secondary
        }
    }

    private var powerSymbol: String {
        switch monitor.powerSnapshot.source {
        case .ac: return "powerplug.fill"
        case .battery: return "battery.75percent"
        case .ups: return "bolt.horizontal.fill"
        case .unknown: return "bolt"
        }
    }

    private var systemHeadline: String {
        if let cpu = monitor.diagnostics.cpuUsagePercent {
            return "CPU \(Int(cpu.rounded()))%"
        }
        return "CPU —"
    }

    private var thermalColor: Color {
        switch monitor.diagnostics.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }

    private var healthName: String {
        if monitor.diagnostics.thermalState == .critical
            || intelligence.state == .critical
            || monitor.pressure == .critical
            || monitor.storageVolumes.contains(where: { $0.health == .critical }) {
            return "Critical"
        }

        if monitor.diagnostics.thermalState == .serious
            || intelligence.state == .pressure
            || intelligence.state == .activeSwap
            || monitor.pressure == .warning
            || monitor.storageVolumes.contains(where: { $0.health == .warning }) {
            return "Attention"
        }

        return "Good"
    }

    private var healthColor: Color {
        switch healthName {
        case "Critical": return .red
        case "Attention": return .orange
        default: return .green
        }
    }

    private var pressureExplanation: String {
        switch monitor.pressure {
        case .normal: return "Your Mac still has comfortable memory headroom."
        case .warning: return "Memory pressure is elevated. Watch compression and swap activity."
        case .critical: return "Memory pressure is critical and may affect responsiveness."
        }
    }

    private var swapExplanation: String {
        switch intelligence.state {
        case .stable: return "No meaningful swap pressure is active."
        case .idleSwap: return "Swap contains old data, but there is no current disk pressure."
        case .readback: return "macOS is reading previously swapped memory back into RAM."
        case .activeSwap: return "Memory pages are actively moving to or from disk."
        case .pressure: return "Sustained pressure and swap activity are present."
        case .critical: return "Swap activity is sustained under critical memory pressure."
        }
    }

    private var headerSummary: String {
        if monitor.diagnostics.thermalState == .critical { return "System thermal state is critical" }
        if monitor.diagnostics.thermalState == .serious { return "System is running hot" }
        if let criticalVolume = monitor.storageVolumes.first(where: { $0.health == .critical }) {
            return "\(criticalVolume.name) is critically low on space"
        }
        if let warningVolume = monitor.storageVolumes.first(where: { $0.health == .warning }) {
            return "\(warningVolume.name) is running low on space"
        }
        return intelligence.summary
    }

    private var statusSymbol: String {
        if monitor.diagnostics.thermalState == .critical { return "thermometer.high" }
        if monitor.storageVolumes.contains(where: { $0.health == .critical }) {
            return "externaldrive.badge.exclamationmark"
        }

        switch intelligence.state {
        case .stable: return "checkmark.circle.fill"
        case .idleSwap: return "pause.circle.fill"
        case .readback: return "arrow.down.circle.fill"
        case .activeSwap: return "arrow.left.arrow.right.circle.fill"
        case .pressure: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        if monitor.diagnostics.thermalState == .critical { return .red }
        if monitor.diagnostics.thermalState == .serious { return .orange }
        if monitor.storageVolumes.contains(where: { $0.health == .critical }) { return .red }
        if monitor.storageVolumes.contains(where: { $0.health == .warning }) && intelligence.state == .stable {
            return .orange
        }

        switch intelligence.state {
        case .stable: return .green
        case .idleSwap: return .secondary
        case .readback: return .blue
        case .activeSwap, .pressure: return .orange
        case .critical: return .red
        }
    }

    private var pressureColor: Color {
        switch monitor.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func storageColor(_ health: StorageHealthState) -> Color {
        switch health {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var notificationPermissionColor: Color {
        switch monitor.notificationAuthorization {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined, .unknown: return .secondary
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func shortBytes(_ value: UInt64) -> String {
        if value == 0 { return "Zero KB" }
        return bytes(value)
    }

    private func fileBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

}

private struct MemoryDonutChart: View {
    let snapshot: MemorySnapshot

    private struct Segment {
        let name: String
        let bytes: UInt64
        let color: Color
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 24)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let start = startFraction(at: index)
                let end = start + fraction(for: segment)

                if end > start {
                    Circle()
                        .trim(from: start, to: max(start, end - 0.008))
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 24, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }

            VStack(spacing: 2) {
                Text(bytes(snapshot.availableBytes))
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("of \(bytes(snapshot.totalBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("available headroom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory Used breakdown")
        .accessibilityValue("\(bytes(snapshot.availableBytes)) of \(bytes(snapshot.totalBytes))")
    }

    private var segments: [Segment] {
        return [
            Segment(name: "App Memory", bytes: snapshot.appMemoryBytes, color: .cyan),
            Segment(name: "Wired", bytes: snapshot.wiredBytes, color: .blue),
            Segment(name: "Compressed", bytes: snapshot.compressedBytes, color: .indigo)
        ]
    }

    private var segmentTotal: Double {
        max(Double(segments.reduce(UInt64(0)) { partial, segment in
            let (sum, overflow) = partial.addingReportingOverflow(segment.bytes)
            return overflow ? UInt64.max : sum
        }), 1)
    }

    private func fraction(for segment: Segment) -> Double {
        min(max(Double(segment.bytes) / segmentTotal, 0), 1)
    }

    private func startFraction(at index: Int) -> Double {
        guard index > 0 else { return 0 }
        return segments.prefix(index).reduce(0) { $0 + fraction(for: $1) }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

}
