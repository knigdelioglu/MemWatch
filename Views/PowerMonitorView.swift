import SwiftUI

struct PowerMonitorView: View {
    let snapshot: PowerSnapshot
    let history: [PowerHistoryPoint]
    let averageWatts: Double?

    @State private var selectedWindow: PowerHistoryWindow = .fifteenMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heroCard
            metricStrip
            PowerFlowCard(snapshot: snapshot)
            historyCard
            sensorCard
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
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

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 16) {
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

            VStack(alignment: .trailing, spacing: 6) {
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
                    Text("Mac, adapter input and battery flow")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Window", selection: $selectedWindow) {
                    ForEach(PowerHistoryWindow.allCases) { window in
                        Text(window.shortName).tag(window)
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
                    chartLegend("Mac", color: .primary)
                    chartLegend("Input", color: .blue)
                    chartLegend("Battery", color: .green)
                    Spacer()
                }

                HStack {
                    summaryValue("Avg", value: visibleAverageWatts ?? averageWatts)
                    Spacer()
                    summaryValue("Peak", value: visiblePeakWatts)
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

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Electrical Details")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(snapshot.source.displayName, systemImage: sourceSymbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            sensorRow("Live input", value: snapshot.adapterInputWatts.map(wattString) ?? "—")
            sensorRow("Mac load", value: snapshot.systemLoadWatts.map(wattString) ?? "—")
            sensorRow("Battery flow", value: signedBatteryString)

            if let ratedWatts = snapshot.adapterRatedWatts {
                sensorRow("Adapter capacity", value: integerWattString(ratedWatts))
            }
            if let voltage = snapshot.voltageMilliVolts {
                sensorRow("Battery voltage", value: String(format: "%.2f V", voltage / 1_000))
            }
            if let current = snapshot.currentMilliAmps {
                sensorRow("Battery current", value: String(format: "%+.2f A", current / 1_000))
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
        Array(history.suffix(selectedWindow.sampleCount))
    }

    private var visibleAverageWatts: Double? {
        let values = visibleHistory.compactMap { $0.systemLoadWatts }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var visiblePeakWatts: Double? {
        visibleHistory.compactMap { $0.systemLoadWatts }.max()
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
        if snapshot.flow == .charging { return "battery.100percent.bolt" }
        if snapshot.flow == .discharging { return "battery.50percent" }
        return "battery.100percent"
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
        case .detailed:
            return "Measured by AppleSmartBattery telemetry"
        case .derived:
            return "Derived from input and battery flow"
        case .batteryOnly:
            return snapshot.source == .battery ? "Measured from battery output" : "Battery telemetry only"
        case .unavailable:
            return "Live power telemetry unavailable"
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
        if snapshot.flow == .discharging,
           snapshot.source == .battery,
           let minutes = snapshot.timeToEmptyMinutes {
            return timeString(minutes) + " remaining"
        }
        return nil
    }

    private var accuracyNote: String {
        switch snapshot.telemetryCoverage {
        case .detailed:
            return "Input and Mac load come from AppleSmartBattery PowerTelemetryData. Battery direction uses signed battery current × voltage. Adapter capacity is the negotiated/rated ceiling, not live draw."
        case .derived:
            return "Live adapter input is measured by AppleSmartBattery. Mac load is calculated from input minus signed battery flow."
        case .batteryOnly:
            return "This Mac is exposing battery electrical telemetry but not detailed external-input telemetry. Battery discharge still gives a useful Mac-load reading while unplugged."
        case .unavailable:
            return "Detailed power sensors are not exposed on this Mac/macOS combination right now. MemWatch leaves unavailable values blank instead of substituting adapter rating."
        }
    }

    private func chartLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryValue(_ title: String, value: Double?) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map(wattString) ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }

    private func sensorRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
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

private enum PowerHistoryWindow: Int, CaseIterable, Identifiable {
    case fiveMinutes = 60
    case fifteenMinutes = 180
    case thirtyMinutes = 360

    var id: Int { rawValue }
    var sampleCount: Int { rawValue }

    var shortName: String {
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power Flow")
                        .font(.subheadline.weight(.semibold))
                    Text(flowDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                sourceNodes
                    .frame(width: 88)

                PowerRibbonDiagram(snapshot: snapshot)
                    .frame(maxWidth: .infinity, minHeight: 116)

                destinationNodes
                    .frame(width: 88)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    @ViewBuilder
    private var sourceNodes: some View {
        if snapshot.source == .battery {
            VStack {
                Spacer()
                flowNode(
                    title: "Battery",
                    value: snapshot.batteryDischargeWatts,
                    symbol: "battery.75percent",
                    color: .orange
                )
                Spacer()
            }
        } else if (snapshot.batteryDischargeWatts ?? 0) > 0.15 {
            VStack(spacing: 10) {
                flowNode(
                    title: "Adapter",
                    value: snapshot.adapterInputWatts,
                    symbol: "powerplug.fill",
                    color: .blue
                )
                flowNode(
                    title: "Battery",
                    value: snapshot.batteryDischargeWatts,
                    symbol: "battery.50percent",
                    color: .orange
                )
            }
        } else {
            VStack {
                Spacer()
                flowNode(
                    title: "Adapter",
                    value: snapshot.adapterInputWatts,
                    symbol: "powerplug.fill",
                    color: .blue
                )
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var destinationNodes: some View {
        if (snapshot.batteryChargeWatts ?? 0) > 0.15 {
            VStack(spacing: 10) {
                flowNode(
                    title: "Mac",
                    value: snapshot.systemLoadWatts,
                    symbol: "laptopcomputer",
                    color: .primary
                )
                flowNode(
                    title: "Battery",
                    value: snapshot.batteryChargeWatts,
                    symbol: "battery.100percent.bolt",
                    color: .green
                )
            }
        } else {
            VStack {
                Spacer()
                flowNode(
                    title: "Mac",
                    value: snapshot.systemLoadWatts,
                    symbol: "laptopcomputer",
                    color: .primary
                )
                Spacer()
            }
        }
    }

    private func flowNode(title: String, value: Double?, symbol: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.semibold))
            Text(value.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var flowDescription: String {
        if snapshot.source == .battery {
            return "Battery powers the Mac"
        }
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
        GeometryReader { proxy in
            Canvas { context, size in
                let maxPower = max(
                    snapshot.systemLoadWatts ?? 0,
                    snapshot.adapterInputWatts ?? 0,
                    snapshot.batteryFlowWatts ?? 0,
                    1
                )

                if snapshot.source == .battery {
                    drawRibbon(
                        context: &context,
                        size: size,
                        startY: size.height * 0.50,
                        endY: size.height * 0.50,
                        watts: snapshot.batteryDischargeWatts ?? snapshot.systemLoadWatts ?? 0,
                        maxPower: maxPower,
                        color: .orange
                    )
                    return
                }

                if (snapshot.batteryDischargeWatts ?? 0) > 0.15 {
                    drawRibbon(
                        context: &context,
                        size: size,
                        startY: size.height * 0.28,
                        endY: size.height * 0.50,
                        watts: snapshot.adapterInputWatts ?? 0,
                        maxPower: maxPower,
                        color: .blue
                    )
                    drawRibbon(
                        context: &context,
                        size: size,
                        startY: size.height * 0.72,
                        endY: size.height * 0.50,
                        watts: snapshot.batteryDischargeWatts ?? 0,
                        maxPower: maxPower,
                        color: .orange
                    )
                    return
                }

                if (snapshot.batteryChargeWatts ?? 0) > 0.15 {
                    drawRibbon(
                        context: &context,
                        size: size,
                        startY: size.height * 0.50,
                        endY: size.height * 0.28,
                        watts: snapshot.systemLoadWatts ?? 0,
                        maxPower: maxPower,
                        color: .blue
                    )
                    drawRibbon(
                        context: &context,
                        size: size,
                        startY: size.height * 0.50,
                        endY: size.height * 0.72,
                        watts: snapshot.batteryChargeWatts ?? 0,
                        maxPower: maxPower,
                        color: .green
                    )
                    return
                }

                drawRibbon(
                    context: &context,
                    size: size,
                    startY: size.height * 0.50,
                    endY: size.height * 0.50,
                    watts: snapshot.systemLoadWatts ?? snapshot.adapterInputWatts ?? 0,
                    maxPower: maxPower,
                    color: .blue
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power flow diagram")
    }

    private func drawRibbon(
        context: inout GraphicsContext,
        size: CGSize,
        startY: CGFloat,
        endY: CGFloat,
        watts: Double,
        maxPower: Double,
        color: Color
    ) {
        let normalized = min(max(watts / maxPower, 0), 1)
        let thickness = CGFloat(7 + normalized * 23)
        let controlX = size.width * 0.48

        var path = Path()
        path.move(to: CGPoint(x: 0, y: startY - thickness / 2))
        path.addCurve(
            to: CGPoint(x: size.width, y: endY - thickness / 2),
            control1: CGPoint(x: controlX, y: startY - thickness / 2),
            control2: CGPoint(x: size.width - controlX, y: endY - thickness / 2)
        )
        path.addLine(to: CGPoint(x: size.width, y: endY + thickness / 2))
        path.addCurve(
            to: CGPoint(x: 0, y: startY + thickness / 2),
            control1: CGPoint(x: size.width - controlX, y: endY + thickness / 2),
            control2: CGPoint(x: controlX, y: startY + thickness / 2)
        )
        path.closeSubpath()

        context.fill(path, with: .color(color.opacity(0.48)))
    }
}

private struct PowerTrendGraph: View {
    let points: [PowerHistoryPoint]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawGrid(context: &context, size: size)

                let maxValue = chartMaximum
                guard maxValue > 0 else { return }

                let systemValues = points.map { $0.systemLoadWatts }
                let inputValues = points.map { $0.adapterInputWatts }
                let batteryValues = points.map { $0.batteryFlowWatts }

                if let area = areaPath(values: systemValues, maxValue: maxValue, size: size) {
                    context.fill(area, with: .color(Color.primary.opacity(0.07)))
                }

                if let systemPath = linePath(values: systemValues, maxValue: maxValue, size: size) {
                    context.stroke(systemPath, with: .color(.primary), lineWidth: 1.8)
                }
                if let inputPath = linePath(values: inputValues, maxValue: maxValue, size: size) {
                    context.stroke(inputPath, with: .color(.blue), lineWidth: 1.45)
                }
                if let batteryPath = linePath(values: batteryValues, maxValue: maxValue, size: size) {
                    context.stroke(batteryPath, with: .color(.green), lineWidth: 1.35)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power history graph")
    }

    private var chartMaximum: Double {
        let values = points.flatMap { point -> [Double] in
            [point.systemLoadWatts, point.adapterInputWatts, point.batteryFlowWatts].compactMap { $0 }
        }
        return max(values.max() ?? 1, 1)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.50, 0.75] {
            let y = size.height * fraction
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color.secondary.opacity(0.12)), lineWidth: 0.7)
        }
    }

    private func linePath(values: [Double?], maxValue: Double, size: CGSize) -> Path? {
        guard values.count > 1 else { return nil }
        let step = size.width / CGFloat(max(values.count - 1, 1))
        var path = Path()
        var started = false

        for (index, value) in values.enumerated() {
            guard let value, value.isFinite else {
                started = false
                continue
            }

            let x = CGFloat(index) * step
            let normalized = min(max(value / maxValue, 0), 1)
            let y = size.height - CGFloat(normalized) * (size.height - 6) - 3
            let point = CGPoint(x: x, y: y)

            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }

        return path
    }

    private func areaPath(values: [Double?], maxValue: Double, size: CGSize) -> Path? {
        guard values.count > 1,
              values.allSatisfy({ $0 != nil }) else { return nil }

        let step = size.width / CGFloat(max(values.count - 1, 1))
        var path = Path()

        for (index, optionalValue) in values.enumerated() {
            guard let value = optionalValue else { continue }
            let x = CGFloat(index) * step
            let normalized = min(max(value / maxValue, 0), 1)
            let y = size.height - CGFloat(normalized) * (size.height - 6) - 3
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
