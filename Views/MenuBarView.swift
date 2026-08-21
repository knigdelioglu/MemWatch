import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MonitoringService

    private var snapshot: MemorySnapshot {
        monitor.snapshot
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
        .frame(width: 300)
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
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Swap")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if monitor.isActivelySwapping {
                    Label("Active", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            metricRow("Used", value: bytes(snapshot.swapUsedBytes))
            metricRow("Total", value: bytes(snapshot.swapTotalBytes))

            if monitor.swapDeltaBytes != 0 {
                metricRow("Allocated Δ / 5 sec", value: signedBytes(monitor.swapDeltaBytes))
            }

            if monitor.swapInDeltaBytes > 0 {
                metricRow("Swap-in / 5 sec", value: bytes(monitor.swapInDeltaBytes))
            }

            if monitor.swapOutDeltaBytes > 0 {
                metricRow("Swap-out / 5 sec", value: bytes(monitor.swapOutDeltaBytes))
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(monitor.pressure.displayName, systemImage: "gauge.with.dots.needle.50percent")
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Text(monitor.isUsingNativePressure ? "macOS pressure event" : "MemWatch estimate")
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

    private var statusText: String {
        if monitor.swapOutDeltaBytes > 0 {
            return "RAM is actively writing to swap"
        }

        if monitor.swapInDeltaBytes > 0 {
            return "Data is being read back from swap"
        }

        switch monitor.pressure {
        case .normal: return "Memory pressure is normal"
        case .warning: return "Memory pressure is elevated"
        case .critical: return "Memory pressure is critical"
        }
    }

    private var statusSymbol: String {
        if monitor.isActivelySwapping {
            return "arrow.left.arrow.right.circle.fill"
        }

        switch monitor.pressure {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        if monitor.swapOutDeltaBytes > 0 {
            return .red
        }

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
