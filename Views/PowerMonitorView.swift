import SwiftUI

struct PowerMonitorView: View {
    let snapshot: PowerSnapshot
    let history: [PowerHistoryPoint]
    let averageWatts: Double?

    @State private var window: PowerHistoryWindow = .fifteenMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero
            metricStrip
            PowerFlowCard(snapshot: snapshot)
            historyCard
            electricalDetails
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Power")
                    .font(.headline)
                Text("Live electrical flow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(snapshot.telemetryCoverage.displayName, systemImage: telemetrySymbol)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.primary.opacity(0.06), in: Capsule())
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MAC DRAW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(snapshot.systemLoadWatts.map(wattString) ?? "—")
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.8)

                Text(systemPowerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol)
                        .font(.title2)
                        .foregroundStyle(flowColor)
                    if let percent = snapshot.batteryPercentClamped {
                        Text("\(percent)%")
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }

                Text(snapshot.flow.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(flowColor)

                if let time = relevantTimeText {
                    Text(time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(flowColor.opacity(0.22), lineWidth: 1)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 9) {
            PowerMetricTile(
                title: "INPUT",
                value: snapshot.adapterInputWatts.map(wattString) ?? "—",
                subtitle: snapshot.source == .ac ? "from adapter" : "not connected",
                symbol: "powerplug.fill",
                tint: .blue
            )
            PowerMetricTile(
                title: "MAC",
                value: snapshot.systemLoadWatts.map(wattString) ?? "—",
                subtitle: "system load",
                symbol: "laptopcomputer",
                tint: .primary
            )
            PowerMetricTile(
                title: "BATTERY",
                value: batteryMetricValue,
                subtitle: batteryMetricSubtitle,
                symbol: "battery.75percent",
                tint: flowColor
            )
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power History")
                        .font(.subheadline.weight(.semibold))
                    Text("Mac · Input · Battery")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Window", selection: $window) {
                    ForEach(PowerHistoryWindow.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 146)
            }

            if visibleHistory.count > 1 {
                PowerTrendGraph(points: visibleHistory)
                    .frame(height: 112)

                HStack(spacing: 12) {
                    legend("Mac", color: .primary)
                    legend("Input", color: .blue)
                    legend("Battery", color: .green)
                    Spacer()
                }

                HStack {
                    summary("Avg", value: visibleAverage ?? averageWatts)
                    Spacer()
                    summary("Peak", value: visiblePeak)
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Collecting power history…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var electricalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Electrical Details")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(snapshot.source.displayName, systemImage: sourceSymbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            detailRow("Live input", snapshot.adapterInputWatts.map(wattString) ?? "—")
            detailRow("Mac load", snapshot.systemLoadWatts.map(wattString) ?? "—")
            detailRow("Battery flow", signedBatteryString)

            if let rated = snapshot.adapterRatedWatts {
                detailRow("Adapter capacity", String(format: "%.0f W", rated))
            }
            if let voltage = snapshot.voltageMilliVolts {
                detailRow("Battery voltage", String(format: "%.2f V", voltage / 1_000))
            }
            if let current = snapshot.currentMilliAmps {
                detailRow("Battery current", String(format: "%+.2f A", current / 1_000))
            }

            Divider()

            Text(accuracyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var visibleHistory: [PowerHistoryPoint] {
        Array(history.suffix(window.sampleCount))
    }

    private var visibleAverage: Double? {
        let values = visibleHistory.compactMap(\.systemLoadWatts)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var visiblePeak: Double? {
        visibleHistory.compactMap(\.systemLoadWatts).max()
    }

    private var telemetrySymbol: String {
        switch snapshot.telemetryCoverage {
        case .detailed: return "waveform.path.ecg"
        case .derived: return "equal.circle"
        case .batteryOnly: return "battery.75percent"
        case .unavailable: return "questionmark.circle"
        }
    }

    private var sourceSymbol: String {
        switch snapshot.source {
        case .ac: return "powerplug.fill"
        case .battery: return "battery.75percent"
        case .ups: return "bolt.horizontal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var batterySymbol: String {
        switch snapshot.flow {
        case .charging: return "battery.100percent.bolt"
        case .discharging: return "battery.50percent"
        case .idle, .unavailable: return "battery.100percent"
        }
    }

    private var flowColor: Color {
        switch snapshot.flow {
        case .charging: return .green
        case .discharging: return .orange
        case .idle: return .blue
        case .unavailable: return .secondary
        }
    }

    private var systemPowerSubtitle: String {
        switch snapshot.telemetryCoverage {
        case .detailed: return "Measured by AppleSmartBattery telemetry"
        case .derived: return "Derived from input and battery flow"
        case .batteryOnly:
            return snapshot.source == .battery ? "Measured from battery output" : "Battery telemetry only"
        case .unavailable: return "Live power telemetry unavailable"
        }
    }

    private var batteryMetricValue: String {
        guard let signed = snapshot.signedBatteryWatts else { return "—" }
        return String(format: "%+.1f W", signed)
    }

    private var batteryMetricSubtitle: String {
        switch snapshot.flow {
        case .charging: return "into battery"
        case .discharging: return "from battery"
        case .idle: return "no flow"
        case .unavailable: return "unavailable"
        }
    }

    private var signedBatteryString: String {
        guard let signed = snapshot.signedBatteryWatts else { return "—" }
        if abs(signed) < 0.15 { return "0.0 W · idle" }
        if signed > 0 { return String(format: "+%.1f W · charging", signed) }
        return String(format: "%.1f W · discharging", signed)
    }

    private var relevantTimeText: String? {
        if snapshot.flow == .charging, let minutes = snapshot.timeToFullMinutes {
            return timeString(minutes) + " to full"
        }
        if snapshot.source == .battery,
           snapshot.flow == .discharging,
           let minutes = snapshot.timeToEmptyMinutes {
            return timeString(minutes) + " remaining"
        }
        return nil
    }

    private var accuracyNote: String {
        switch snapshot.telemetryCoverage {
        case .detailed:
            return "Input and Mac load use AppleSmartBattery PowerTelemetryData. Battery direction uses signed current × voltage. Adapter capacity is a ceiling, not live draw."
        case .derived:
            return "Live adapter input is measured. Mac load is calculated from input minus signed battery flow."
        case .batteryOnly:
            return "Detailed external-input telemetry is unavailable. While unplugged, battery discharge still provides the Mac-load reading."
        case .unavailable:
            return "Detailed power sensors are unavailable on this Mac/macOS combination. MemWatch leaves missing values blank instead of using adapter rating as live draw."
        }
    }

    private func wattString(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func timeString(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func summary(_ title: String, value: Double?) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.map(wattString) ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

private enum PowerHistoryWindow: Int, CaseIterable, Identifiable {
    case fiveMinutes = 60
    case fifteenMinutes = 180
    case thirtyMinutes = 360

    var id: Int { rawValue }
    var sampleCount: Int { rawValue }

    var label: String {
        switch self {
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        }
    }
}

private struct PowerMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PowerFlowCard: View {
    let snapshot: PowerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Power Flow")
                    .font(.subheadline.weight(.semibold))
                Text(flowDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                sourceColumn.frame(width: 88)
                PowerRibbonDiagram(snapshot: snapshot)
                    .frame(maxWidth: .infinity, minHeight: 116)
                destinationColumn.frame(width: 88)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    @ViewBuilder
    private var sourceColumn: some View {
        if snapshot.source == .battery {
            VStack {
                Spacer()
                node("Battery", snapshot.batteryDischargeWatts, "battery.75percent", .orange)
                Spacer()
            }
        } else if (snapshot.batteryDischargeWatts ?? 0) > 0.15 {
            VStack(spacing: 10) {
                node("Adapter", snapshot.adapterInputWatts, "powerplug.fill", .blue)
                node("Battery", snapshot.batteryDischargeWatts, "battery.50percent", .orange)
            }
        } else {
            VStack {
                Spacer()
                node("Adapter", snapshot.adapterInputWatts, "powerplug.fill", .blue)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var destinationColumn: some View {
        if (snapshot.batteryChargeWatts ?? 0) > 0.15 {
            VStack(spacing: 10) {
                node("Mac", snapshot.systemLoadWatts, "laptopcomputer", .primary)
                node("Battery", snapshot.batteryChargeWatts, "battery.100percent", .green)
            }
        } else {
            VStack {
                Spacer()
                node("Mac", snapshot.systemLoadWatts, "laptopcomputer", .primary)
                Spacer()
            }
        }
    }

    private func node(_ title: String, _ watts: Double?, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(title).font(.caption2.weight(.semibold))
            Text(watts.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var flowDescription: String {
        if snapshot.source == .battery { return "Battery powers the Mac" }
        if (snapshot.batteryDischargeWatts ?? 0) > 0.15 {
            return "Adapter and battery are powering the Mac"
        }
        if (snapshot.batteryChargeWatts ?? 0) > 0.15 {
            return "Adapter power is split between Mac and battery"
        }
        return "Adapter powers the Mac directly"
    }
}

private struct PowerRibbonDiagram: View {
    let snapshot: PowerSnapshot

    var body: some View {
        Canvas { context, size in
            let maxPower = [
                snapshot.systemLoadWatts ?? 0,
                snapshot.adapterInputWatts ?? 0,
                snapshot.batteryFlowWatts ?? 0,
                1
            ].max() ?? 1

            if snapshot.source == .battery {
                ribbon(
                    context: &context,
                    size: size,
                    from: 0.5,
                    to: 0.5,
                    watts: snapshot.batteryDischargeWatts ?? snapshot.systemLoadWatts ?? 0,
                    maxPower: maxPower,
                    color: .orange
                )
            } else if (snapshot.batteryDischargeWatts ?? 0) > 0.15 {
                ribbon(context: &context, size: size, from: 0.28, to: 0.5, watts: snapshot.adapterInputWatts ?? 0, maxPower: maxPower, color: .blue)
                ribbon(context: &context, size: size, from: 0.72, to: 0.5, watts: snapshot.batteryDischargeWatts ?? 0, maxPower: maxPower, color: .orange)
            } else if (snapshot.batteryChargeWatts ?? 0) > 0.15 {
                ribbon(context: &context, size: size, from: 0.5, to: 0.28, watts: snapshot.systemLoadWatts ?? 0, maxPower: maxPower, color: .blue)
                ribbon(context: &context, size: size, from: 0.5, to: 0.72, watts: snapshot.batteryChargeWatts ?? 0, maxPower: maxPower, color: .green)
            } else {
                ribbon(context: &context, size: size, from: 0.5, to: 0.5, watts: snapshot.systemLoadWatts ?? snapshot.adapterInputWatts ?? 0, maxPower: maxPower, color: .blue)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power flow diagram")
    }

    private func ribbon(
        context: inout GraphicsContext,
        size: CGSize,
        from startFraction: CGFloat,
        to endFraction: CGFloat,
        watts: Double,
        maxPower: Double,
        color: Color
    ) {
        let startY = size.height * startFraction
        let endY = size.height * endFraction
        let normalized = min(max(watts / maxPower, 0), 1)
        let thickness = CGFloat(7 + normalized * 23)
        let c1 = size.width * 0.42
        let c2 = size.width * 0.58

        var path = Path()
        path.move(to: CGPoint(x: 0, y: startY - thickness / 2))
        path.addCurve(
            to: CGPoint(x: size.width, y: endY - thickness / 2),
            control1: CGPoint(x: c1, y: startY - thickness / 2),
            control2: CGPoint(x: c2, y: endY - thickness / 2)
        )
        path.addLine(to: CGPoint(x: size.width, y: endY + thickness / 2))
        path.addCurve(
            to: CGPoint(x: 0, y: startY + thickness / 2),
            control1: CGPoint(x: c2, y: endY + thickness / 2),
            control2: CGPoint(x: c1, y: startY + thickness / 2)
        )
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.48)))
    }
}

private struct PowerTrendGraph: View {
    let points: [PowerHistoryPoint]

    var body: some View {
        Canvas { context, size in
            grid(context: &context, size: size)

            let maximum = chartMaximum
            guard maximum > 0 else { return }

            if let path = linePath(\.systemLoadWatts, maximum: maximum, size: size) {
                context.stroke(path, with: .color(Color.primary), lineWidth: 1.8)
            }
            if let path = linePath(\.adapterInputWatts, maximum: maximum, size: size) {
                context.stroke(path, with: .color(Color.blue), lineWidth: 1.45)
            }
            if let path = linePath(\.batteryFlowWatts, maximum: maximum, size: size) {
                context.stroke(path, with: .color(Color.green), lineWidth: 1.35)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power history graph")
    }

    private var chartMaximum: Double {
        let values = points.flatMap { point in
            [point.systemLoadWatts, point.adapterInputWatts, point.batteryFlowWatts].compactMap { $0 }
        }
        return max(values.max() ?? 1, 1)
    }

    private func grid(context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
            let y = size.height * fraction
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color.secondary.opacity(0.12)), lineWidth: 0.7)
        }
    }

    private func linePath(
        _ keyPath: KeyPath<PowerHistoryPoint, Double?>,
        maximum: Double,
        size: CGSize
    ) -> Path? {
        guard points.count > 1 else { return nil }
        let step = size.width / CGFloat(max(points.count - 1, 1))
        var path = Path()
        var hasSegment = false

        for (index, point) in points.enumerated() {
            guard let value = point[keyPath: keyPath], value.isFinite else {
                hasSegment = false
                continue
            }

            let x = CGFloat(index) * step
            let normalized = min(max(value / maximum, 0), 1)
            let y = size.height - CGFloat(normalized) * (size.height - 6) - 3
            let next = CGPoint(x: x, y: y)

            if hasSegment {
                path.addLine(to: next)
            } else {
                path.move(to: next)
                hasSegment = true
            }
        }

        return path
    }
}
