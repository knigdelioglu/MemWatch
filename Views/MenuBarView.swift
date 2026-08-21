import SwiftUI

struct MenuBarView: View {
    let snapshot: MemorySnapshot
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            memorySummary
            Divider()
            memoryBreakdown
            Divider()
            swapSummary
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Label("MemWatch", systemImage: "memorychip")
                .font(.headline)

            Spacer()

            Text(snapshot.pressure.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(pressureColor)
        }
    }

    private var memorySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(snapshot.usedPercent)%")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: snapshot.usedFraction)
                .tint(pressureColor)

            HStack {
                Text("Used \(bytes(snapshot.usedBytes))")
                Spacer()
                Text("Available \(bytes(snapshot.availableBytes))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var memoryBreakdown: some View {
        VStack(spacing: 7) {
            metricRow("App Memory", value: snapshot.appMemoryBytes)
            metricRow("Wired", value: snapshot.wiredBytes)
            metricRow("Compressed", value: snapshot.compressedBytes)
            metricRow("Cached Files", value: snapshot.cachedBytes)
            metricRow("Free", value: snapshot.freeBytes)
        }
    }

    private var swapSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Swap")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if snapshot.isActivelySwapping {
                    Label("Active", systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(snapshot.isActivelySwappingOut ? .orange : .secondary)
                } else {
                    Text("Idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            metricRow("Used", valueText: bytes(snapshot.swapUsedBytes))
            metricRow("Read", valueText: rate(snapshot.swapInRateBytesPerSecond))
            metricRow("Write", valueText: rate(snapshot.swapOutRateBytesPerSecond))
        }
    }

    private var footer: some View {
        HStack {
            Text("Updates every 2 seconds")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Refresh") {
                refreshAction()
            }
            .controlSize(.small)
        }
    }

    private func metricRow(_ title: String, value: UInt64) -> some View {
        metricRow(title, valueText: bytes(value))
    }

    private func metricRow(_ title: String, valueText: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valueText)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private var pressureColor: Color {
        switch snapshot.pressure {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: value),
            countStyle: .memory
        )
    }

    private func rate(_ value: Double) -> String {
        guard value > 0 else {
            return "0 B/s"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true

        return "\(formatter.string(fromByteCount: Int64(value.rounded())))/s"
    }
}
