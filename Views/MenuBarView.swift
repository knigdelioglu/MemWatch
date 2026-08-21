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
                Text("Swap & Paging")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if monitor.isActivelySwapping {
                    Label("Active", systemImage: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            metricRow("Swap used", value: bytes(snapshot.swapUsedBytes))
            metricRow("Swap total", value: bytes(snapshot.swapTotalBytes))

            if monitor.swapDeltaBytes != 0 {
                metricRow("Swap Δ / 5 sec", value: signedBytes(monitor.swapDeltaBytes))
            }

            if monitor.pageInDeltaBytes > 0 {
                metricRow("Page-in / 5 sec", value: bytes(monitor.pageInDeltaBytes))
            }

            if monitor.pageOutDeltaBytes > 0 {
                metricRow("Page-out / 5 sec", value: bytes(monitor.pageOutDeltaBytes))
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(snapshot.pressure.displayName, systemImage: "gauge.with.dots.needle.50percent")
                .font(.caption)
                .foregroundStyle(statusColor)

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
        if monitor.isActivelySwapping {
            return "Active memory paging detected"
        }

        switch snapshot.pressure {
        case .normal: return "Memory pressure is normal"
        case .warning: return "Memory pressure is elevated"
        case .critical: return "Memory pressure is critical"
        }
    }

    private var statusSymbol: String {
        switch snapshot.pressure {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch snapshot.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func signedBytes(_ value: Int64) -> String {
        let prefix = value > 0 ? "+" : "−"
        let magnitude = value == Int64.min ? UInt64(Int64.max) + 1 : UInt64(abs(value))
        return prefix + bytes(magnitude)
    }
}
