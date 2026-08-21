import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MonitoringService

    private var snapshot: MemorySnapshot {
        monitor.snapshot
    }

    private var intelligence: SwapIntelligenceResult {
        monitor.intelligence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            memorySection
            Divider()
            swapSection
            Divider()
            footer
        }
        .frame(width: 320)
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("MemWatch")
                    .font(.headline)
                Text(intelligence.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text("\(snapshot.usagePercent)%")
                .font(.title3.monospacedDigit())
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memory")
                .font(.subheadline.weight(.semibold))

            ProgressView(value: snapshot.usageRatio)
                .tint(statusColor)

            metricRow("Used", value: bytes(snapshot.usedBytes))
            metricRow("Available", value: bytes(snapshot.availableBytes))
            metricRow("Wired", value: bytes(snapshot.wiredBytes))
            metricRow("Compressed", value: bytes(snapshot.compressedBytes))
            metricRow("Cached", value: bytes(snapshot.cachedBytes))
        }
    }

    private var swapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Swap Intelligence")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label(intelligence.state.displayName, systemImage: intelligenceSymbol)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            metricRow("Swap used", value: bytes(snapshot.swapUsedBytes))

            if monitor.swapDeltaBytes != 0 {
                metricRow("Allocated Δ / 5 sec", value: signedBytes(monitor.swapDeltaBytes))
            }

            if monitor.swapInDeltaBytes > 0 {
                metricRow("Swap-in / 5 sec", value: bytes(monitor.swapInDeltaBytes))
            }

            if monitor.swapOutDeltaBytes > 0 {
                metricRow("Swap-out / 5 sec", value: bytes(monitor.swapOutDeltaBytes))
            }

            if intelligence.recentSwapInBytes > 0 {
                metricRow("Recent swap-in", value: bytes(intelligence.recentSwapInBytes))
            }

            if intelligence.recentSwapOutBytes > 0 {
                metricRow("Recent swap-out", value: bytes(intelligence.recentSwapOutBytes))
            }

            metricRow(
                "Active samples",
                value: "\(intelligence.activeSamples)/\(max(intelligence.sampleCount, 1))"
            )
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(monitor.pressure.displayName, systemImage: "gauge.with.dots.needle.50percent")
                    .font(.caption)
                    .foregroundStyle(pressureColor)

                Text(monitor.isUsingNativePressure ? "macOS pressure event" : "MemWatch pressure estimate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Refresh") {
                monitor.refresh()
            }
            .buttonStyle(.plain)
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private var statusSymbol: String {
        switch intelligence.state {
        case .stable: return "checkmark.circle.fill"
        case .idleSwap: return "pause.circle.fill"
        case .readback: return "arrow.down.circle.fill"
        case .activeSwap: return "arrow.left.arrow.right.circle.fill"
        case .pressure: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var intelligenceSymbol: String {
        switch intelligence.state {
        case .stable: return "checkmark.circle"
        case .idleSwap: return "pause.circle"
        case .readback: return "arrow.down.circle"
        case .activeSwap: return "arrow.left.arrow.right.circle"
        case .pressure: return "gauge.with.dots.needle.67percent"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private var statusColor: Color {
        switch intelligence.state {
        case .stable: return .green
        case .idleSwap: return .secondary
        case .readback: return .blue
        case .activeSwap: return .orange
        case .pressure: return .orange
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

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func signedBytes(_ value: Int64) -> String {
        guard value != 0 else { return bytes(0) }
        let prefix = value > 0 ? "+" : "−"
        let magnitude = value == Int64.min ? UInt64(Int64.max) + 1 : UInt64(abs(value))
        return prefix + bytes(magnitude)
    }
}
