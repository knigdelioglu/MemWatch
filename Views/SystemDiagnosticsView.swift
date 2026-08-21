import SwiftUI

struct SystemDiagnosticsView: View {
    let diagnostics: SystemDiagnosticsSnapshot
    let history: [SystemHistoryPoint]
    let fanTelemetry: FanTelemetryState
    let launchAtLoginState: LaunchAtLoginState
    let launchAtLoginError: String?
    let onLaunchAtLoginChange: (Bool) -> Void
    let onRefreshProcesses: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Diagnostics")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label(diagnostics.thermalState.displayName, systemImage: thermalSymbol)
                    .font(.caption)
                    .foregroundStyle(thermalColor)
            }

            HStack(spacing: 16) {
                metricBlock(
                    title: "CPU",
                    value: diagnostics.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—"
                )
                metricBlock(
                    title: "Thermal",
                    value: diagnostics.thermalState.displayName
                )
                metricBlock(
                    title: "Power mode",
                    value: diagnostics.lowPowerModeEnabled ? "Low" : "Normal"
                )
            }

            if history.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("CPU + RAM · 10 min")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        HStack(spacing: 8) {
                            Label("CPU", systemImage: "waveform.path.ecg")
                            Label("RAM", systemImage: "memorychip")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    SystemHistoryGraph(points: history)
                        .frame(height: 62)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Top memory apps")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Refresh") {
                        onRefreshProcesses()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                }

                if diagnostics.topProcesses.isEmpty {
                    Text("No process memory snapshot available yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diagnostics.topProcesses.prefix(6)) { process in
                        HStack(spacing: 8) {
                            Image(systemName: "app.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(process.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(memoryString(process.residentBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Fan telemetry", systemImage: "fan")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Public API unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("MemWatch does not invent fan RPM. Apple does not provide a stable public API for exact fan speed across Macs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(fanTelemetry.displayName)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Toggle(
                    "Launch MemWatch at login",
                    isOn: Binding(
                        get: { launchAtLoginState == .enabled || launchAtLoginState == .requiresApproval },
                        set: { onLaunchAtLoginChange($0) }
                    )
                )
                .toggleStyle(.switch)
                .font(.caption.weight(.semibold))

                HStack {
                    Text("Login item")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(launchAtLoginState.displayName)
                }
                .font(.caption2)

                if launchAtLoginState == .requiresApproval {
                    Text("macOS requires approval in System Settings → General → Login Items.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thermalSymbol: String {
        switch diagnostics.thermalState {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious: return "thermometer.high"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    private var thermalColor: Color {
        switch diagnostics.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }

    private func memoryString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}

private struct SystemHistoryGraph: View {
    let points: [SystemHistoryPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let step = size.width / CGFloat(max(points.count - 1, 1))

            var cpuPath = Path()
            var memoryPath = Path()

            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * step
                let cpu = min(max(point.cpuUsagePercent / 100, 0), 1)
                let memory = min(max(point.memoryUsagePercent / 100, 0), 1)
                let cpuY = size.height - CGFloat(cpu) * (size.height - 4) - 2
                let memoryY = size.height - CGFloat(memory) * (size.height - 4) - 2

                if index == 0 {
                    cpuPath.move(to: CGPoint(x: x, y: cpuY))
                    memoryPath.move(to: CGPoint(x: x, y: memoryY))
                } else {
                    cpuPath.addLine(to: CGPoint(x: x, y: cpuY))
                    memoryPath.addLine(to: CGPoint(x: x, y: memoryY))
                }
            }

            context.stroke(cpuPath, with: .foreground, lineWidth: 1.5)
            context.stroke(
                memoryPath,
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
            )
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("CPU and memory history")
    }
}