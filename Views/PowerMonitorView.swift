import SwiftUI

struct PowerMonitorView: View {
    let snapshot: PowerSnapshot
    let history: [PowerHistoryPoint]
    let averageWatts: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Energy")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label(snapshot.source.displayName, systemImage: sourceSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.observableMetricName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let watts = snapshot.observableWatts {
                        Text(wattString(watts))
                            .font(.title2.monospacedDigit().weight(.semibold))
                    } else {
                        Text("—")
                            .font(.title2.weight(.semibold))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let percent = snapshot.batteryPercentClamped {
                        Text("\(percent)%")
                            .font(.headline.monospacedDigit())
                    }
                    Text(snapshot.flow.displayName)
                        .font(.caption2)
                        .foregroundStyle(flowColor)
                }
            }

            PowerFlowDiagram(snapshot: snapshot)
                .frame(height: snapshot.source == .ac ? 74 : 42)

            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Live power · 10 min")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let averageWatts {
                            Text("Avg \(wattString(averageWatts))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    PowerHistoryGraph(points: history)
                        .frame(height: 62)
                }
            }

            HStack(spacing: 12) {
                if let ratedWatts = snapshot.adapterRatedWatts {
                    Label("\(integerWattString(ratedWatts)) adapter", systemImage: "powerplug.fill")
                }

                if let time = relevantTimeText {
                    Label(time, systemImage: "clock")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(accuracyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceSymbol: String {
        switch snapshot.source {
        case .ac: return "powerplug.fill"
        case .battery: return "battery.50percent"
        case .ups: return "bolt.horizontal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var flowColor: Color {
        switch snapshot.flow {
        case .charging: return .green
        case .discharging: return .orange
        case .idle: return .secondary
        case .unavailable: return .secondary
        }
    }

    private var relevantTimeText: String? {
        if snapshot.flow == .charging, let minutes = snapshot.timeToFullMinutes {
            return timeString(minutes) + " to full"
        }
        if snapshot.flow == .discharging, let minutes = snapshot.timeToEmptyMinutes {
            return timeString(minutes) + " remaining"
        }
        return nil
    }

    private var accuracyNote: String {
        switch snapshot.flow {
        case .discharging:
            return "Mac draw is calculated from live battery current × voltage."
        case .charging:
            return "Charge watts are battery-side power. Adapter wattage is rated capacity, not live wall draw."
        case .idle:
            return "On AC power. Public macOS APIs do not expose exact total Mac wall draw on every model; MemWatch does not estimate it from adapter rating."
        case .unavailable:
            return "Live battery electrical telemetry is unavailable on this Mac right now."
        }
    }

    private func wattString(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func integerWattString(_ value: Double) -> String {
        String(format: "%.0f W", value)
    }

    private func timeString(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }
        return "\(remainder)m"
    }
}

private struct PowerFlowDiagram: View {
    let snapshot: PowerSnapshot

    var body: some View {
        VStack(spacing: 8) {
            if snapshot.source == .battery {
                flowRow(
                    from: "Battery",
                    fromSymbol: "battery.75percent",
                    to: "Mac",
                    toSymbol: "laptopcomputer",
                    active: true,
                    detail: snapshot.batteryFlowWatts.map { String(format: "%.1f W", $0) }
                )
            } else {
                flowRow(
                    from: "Adapter",
                    fromSymbol: "powerplug.fill",
                    to: "Mac",
                    toSymbol: "laptopcomputer",
                    active: snapshot.source == .ac,
                    detail: nil
                )

                flowRow(
                    from: "Adapter",
                    fromSymbol: "powerplug.fill",
                    to: "Battery",
                    toSymbol: "battery.75percent",
                    active: snapshot.flow == .charging,
                    detail: snapshot.flow == .charging
                        ? snapshot.batteryFlowWatts.map { String(format: "%.1f W", $0) }
                        : "Idle"
                )
            }
        }
    }

    private func flowRow(
        from: String,
        fromSymbol: String,
        to: String,
        toSymbol: String,
        active: Bool,
        detail: String?
    ) -> some View {
        HStack(spacing: 8) {
            Label(from, systemImage: fromSymbol)
                .font(.caption2)
                .frame(width: 72, alignment: .leading)

            AnimatedPowerArrow(active: active)
                .frame(height: 14)

            VStack(alignment: .trailing, spacing: 0) {
                Label(to, systemImage: toSymbol)
                    .font(.caption2)
                if let detail {
                    Text(detail)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 74, alignment: .trailing)
        }
    }
}

private struct AnimatedPowerArrow: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                Canvas { context, size in
                    let y = size.height / 2
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))

                    context.stroke(
                        line,
                        with: .foreground,
                        style: StrokeStyle(lineWidth: 1, dash: active ? [] : [3, 3])
                    )

                    var arrow = Path()
                    arrow.move(to: CGPoint(x: size.width - 5, y: y - 3))
                    arrow.addLine(to: CGPoint(x: size.width, y: y))
                    arrow.addLine(to: CGPoint(x: size.width - 5, y: y + 3))
                    context.stroke(arrow, with: .foreground, lineWidth: 1)

                    guard active, size.width > 8 else { return }

                    let seconds = timeline.date.timeIntervalSinceReferenceDate
                    let phase = seconds.truncatingRemainder(dividingBy: 1.4) / 1.4
                    let x = 3 + (size.width - 8) * phase
                    let dot = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: dot), with: .foreground)
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

private struct PowerHistoryGraph: View {
    let points: [PowerHistoryPoint]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let values = points.map(\.watts)
                guard values.count > 1 else { return }

                let maxValue = max(values.max() ?? 1, 1)
                let step = size.width / CGFloat(max(values.count - 1, 1))

                var path = Path()
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * step
                    let normalized = min(max(value / maxValue, 0), 1)
                    let y = size.height - CGFloat(normalized) * (size.height - 4) - 2

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(path, with: .foreground, lineWidth: 1.5)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Live power history")
    }
}
