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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Power Flow")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(flowSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            AlDenteFlowDiagram(snapshot: snapshot)
                .frame(height: 136)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var flowSummary: String {
        if snapshot.source == .battery {
            return "Battery → Mac"
        }
        if (snapshot.batteryDischargeWatts ?? 0) > 0.15 {
            return "Adapter + Battery → Mac"
        }
        if (snapshot.batteryChargeWatts ?? 0) > 0.15 {
            return "Adapter → Mac + Battery"
        }
        if snapshot.source == .ac || snapshot.source == .ups {
            return "Adapter → Mac"
        }
        return "No live route"
    }
}

private struct AlDenteFlowDiagram: View {
    let snapshot: PowerSnapshot

    @Environment(\.colorScheme) private var colorScheme

    private let nodeWidth: CGFloat = 62
    private let separatorWidth: CGFloat = 7
    private let verticalInset: CGFloat = 7
    private let rowGap: CGFloat = 7

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let leftX = nodeWidth + separatorWidth
            let rightX = max(leftX + 12, size.width - nodeWidth - separatorWidth)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(surfaceColor)

                Canvas { context, canvasSize in
                    drawStructure(
                        context: &context,
                        size: canvasSize,
                        leftX: leftX,
                        rightX: rightX
                    )
                    drawFlow(
                        context: &context,
                        size: canvasSize,
                        leftX: leftX,
                        rightX: rightX
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                nodeOverlays(size: size, leftX: leftX, rightX: rightX)
                valueOverlays(size: size, leftX: leftX, rightX: rightX)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.primary.opacity(colorScheme == .dark ? 0.10 : 0.08), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var topology: FlowTopology {
        if snapshot.source == .battery {
            return .batteryToMac
        }
        if (snapshot.batteryDischargeWatts ?? 0) > 0.15,
           snapshot.source == .ac || snapshot.source == .ups {
            return .adapterAndBatteryToMac
        }
        if (snapshot.batteryChargeWatts ?? 0) > 0.15,
           snapshot.source == .ac || snapshot.source == .ups {
            return .adapterToMacAndBattery
        }
        if snapshot.source == .ac || snapshot.source == .ups {
            return .adapterToMac
        }
        return .unavailable
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.055)
    }

    private var nodeSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.075)
    }

    private var separatorColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.20) : Color.white.opacity(0.42)
    }

    private var ribbonStartColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.10)
    }

    private var ribbonEndColor: Color {
        Color.blue.opacity(colorScheme == .dark ? 0.31 : 0.24)
    }

    private func drawStructure(
        context: inout GraphicsContext,
        size: CGSize,
        leftX: CGFloat,
        rightX: CGFloat
    ) {
        fillRect(
            CGRect(x: 0, y: 0, width: nodeWidth, height: size.height),
            color: nodeSurfaceColor,
            context: &context
        )
        fillRect(
            CGRect(x: size.width - nodeWidth, y: 0, width: nodeWidth, height: size.height),
            color: nodeSurfaceColor,
            context: &context
        )
        fillRect(
            CGRect(x: nodeWidth, y: 0, width: separatorWidth, height: size.height),
            color: separatorColor,
            context: &context
        )
        fillRect(
            CGRect(x: rightX, y: 0, width: separatorWidth, height: size.height),
            color: separatorColor,
            context: &context
        )

        switch topology {
        case .adapterAndBatteryToMac:
            fillRect(
                CGRect(x: 0, y: size.height / 2 - separatorWidth / 2, width: nodeWidth, height: separatorWidth),
                color: separatorColor,
                context: &context
            )
        case .adapterToMacAndBattery:
            fillRect(
                CGRect(
                    x: size.width - nodeWidth,
                    y: size.height / 2 - separatorWidth / 2,
                    width: nodeWidth,
                    height: separatorWidth
                ),
                color: separatorColor,
                context: &context
            )
        default:
            break
        }
    }

    private func drawFlow(
        context: inout GraphicsContext,
        size: CGSize,
        leftX: CGFloat,
        rightX: CGFloat
    ) {
        let top = verticalInset
        let bottom = size.height - verticalInset
        let midpoint = size.height / 2

        switch topology {
        case .adapterToMac, .batteryToMac:
            let path = ribbonPath(
                startX: leftX,
                endX: rightX,
                startTop: top,
                startBottom: bottom,
                endTop: top,
                endBottom: bottom
            )
            fillRibbon(path, startX: leftX, endX: rightX, context: &context)

        case .adapterAndBatteryToMac:
            let total = max(
                (snapshot.adapterInputWatts ?? 0) + (snapshot.batteryDischargeWatts ?? 0),
                0.1
            )
            let adapterRatio = clampedRatio((snapshot.adapterInputWatts ?? 0) / total)
            let available = bottom - top
            let joinedSplit = top + available * CGFloat(adapterRatio)

            let upper = ribbonPath(
                startX: leftX,
                endX: rightX,
                startTop: top,
                startBottom: midpoint - rowGap / 2,
                endTop: top,
                endBottom: joinedSplit
            )
            let lower = ribbonPath(
                startX: leftX,
                endX: rightX,
                startTop: midpoint + rowGap / 2,
                startBottom: bottom,
                endTop: joinedSplit,
                endBottom: bottom
            )
            fillRibbon(upper, startX: leftX, endX: rightX, context: &context)
            fillRibbon(lower, startX: leftX, endX: rightX, context: &context)

        case .adapterToMacAndBattery:
            let total = max(
                (snapshot.systemLoadWatts ?? 0) + (snapshot.batteryChargeWatts ?? 0),
                0.1
            )
            let macRatio = clampedRatio((snapshot.systemLoadWatts ?? 0) / total)
            let available = bottom - top
            let sourceSplit = top + available * CGFloat(macRatio)

            let upper = ribbonPath(
                startX: leftX,
                endX: rightX,
                startTop: top,
                startBottom: sourceSplit,
                endTop: top,
                endBottom: midpoint - rowGap / 2
            )
            let lower = ribbonPath(
                startX: leftX,
                endX: rightX,
                startTop: sourceSplit,
                startBottom: bottom,
                endTop: midpoint + rowGap / 2,
                endBottom: bottom
            )
            fillRibbon(upper, startX: leftX, endX: rightX, context: &context)
            fillRibbon(lower, startX: leftX, endX: rightX, context: &context)

        case .unavailable:
            break
        }
    }

    @ViewBuilder
    private func nodeOverlays(size: CGSize, leftX: CGFloat, rightX: CGFloat) -> some View {
        let leftCenterX = nodeWidth / 2
        let rightCenterX = size.width - nodeWidth / 2
        let upperY = size.height * 0.25
        let lowerY = size.height * 0.75
        let centerY = size.height / 2

        switch topology {
        case .adapterToMac:
            flowNode(symbol: "bolt.fill", accent: .primary)
                .position(x: leftCenterX, y: centerY)
            flowNode(symbol: "laptopcomputer", accent: .blue)
                .position(x: rightCenterX, y: centerY)

        case .batteryToMac:
            flowNode(symbol: "battery.50percent", accent: .primary)
                .position(x: leftCenterX, y: centerY)
            flowNode(symbol: "laptopcomputer", accent: .primary)
                .position(x: rightCenterX, y: centerY)

        case .adapterAndBatteryToMac:
            flowNode(symbol: "bolt.fill", accent: .primary)
                .position(x: leftCenterX, y: upperY)
            flowNode(symbol: "battery.50percent", accent: .primary)
                .position(x: leftCenterX, y: lowerY)
            flowNode(
                symbol: "laptopcomputer",
                accent: .blue,
                value: snapshot.systemLoadWatts.map(wattString)
            )
            .position(x: rightCenterX, y: centerY)

        case .adapterToMacAndBattery:
            flowNode(symbol: "bolt.fill", accent: .primary)
                .position(x: leftCenterX, y: centerY)
            flowNode(symbol: "laptopcomputer", accent: .blue)
                .position(x: rightCenterX, y: upperY)
            flowNode(
                symbol: "battery.100percent",
                accent: .green,
                value: snapshot.batteryPercentClamped.map { "\($0)%" }
            )
            .position(x: rightCenterX, y: lowerY)

        case .unavailable:
            flowNode(symbol: "questionmark", accent: .secondary)
                .position(x: leftCenterX, y: centerY)
            flowNode(symbol: "laptopcomputer", accent: .secondary)
                .position(x: rightCenterX, y: centerY)
        }
    }

    @ViewBuilder
    private func valueOverlays(size: CGSize, leftX: CGFloat, rightX: CGFloat) -> some View {
        let centerX = (leftX + rightX) / 2

        switch topology {
        case .adapterToMac:
            flowValue(snapshot.systemLoadWatts ?? snapshot.adapterInputWatts)
                .position(x: centerX, y: size.height / 2)

        case .batteryToMac:
            flowValue(snapshot.batteryDischargeWatts ?? snapshot.systemLoadWatts)
                .position(x: centerX, y: size.height / 2)

        case .adapterAndBatteryToMac:
            flowValue(snapshot.adapterInputWatts)
                .position(x: centerX, y: size.height * 0.28)
            flowValue(snapshot.batteryDischargeWatts)
                .position(x: centerX, y: size.height * 0.72)

        case .adapterToMacAndBattery:
            flowValue(snapshot.systemLoadWatts)
                .position(x: centerX, y: size.height * 0.28)
            flowValue(snapshot.batteryChargeWatts)
                .position(x: centerX, y: size.height * 0.72)

        case .unavailable:
            Text("—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .position(x: centerX, y: size.height / 2)
        }
    }

    private func flowNode(symbol: String, accent: Color, value: String? = nil) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent)

            if let value {
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(width: nodeWidth - 10)
    }

    private func flowValue(_ watts: Double?) -> some View {
        Text(watts.map(wattString) ?? "—")
            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func fillRect(_ rect: CGRect, color: Color, context: inout GraphicsContext) {
        var path = Path()
        path.addRect(rect)
        context.fill(path, with: .color(color))
    }

    private func fillRibbon(
        _ path: Path,
        startX: CGFloat,
        endX: CGFloat,
        context: inout GraphicsContext
    ) {
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [ribbonStartColor, ribbonEndColor]),
                startPoint: CGPoint(x: startX, y: 0),
                endPoint: CGPoint(x: endX, y: 0)
            )
        )
    }

    private func ribbonPath(
        startX: CGFloat,
        endX: CGFloat,
        startTop: CGFloat,
        startBottom: CGFloat,
        endTop: CGFloat,
        endBottom: CGFloat
    ) -> Path {
        let width = max(endX - startX, 1)
        let control1X = startX + width * 0.42
        let control2X = startX + width * 0.66

        var path = Path()
        path.move(to: CGPoint(x: startX, y: startTop))
        path.addCurve(
            to: CGPoint(x: endX, y: endTop),
            control1: CGPoint(x: control1X, y: startTop),
            control2: CGPoint(x: control2X, y: endTop)
        )
        path.addLine(to: CGPoint(x: endX, y: endBottom))
        path.addCurve(
            to: CGPoint(x: startX, y: startBottom),
            control1: CGPoint(x: control2X, y: endBottom),
            control2: CGPoint(x: control1X, y: startBottom)
        )
        path.closeSubpath()
        return path
    }

    private func clampedRatio(_ value: Double) -> Double {
        min(max(value, 0.18), 0.82)
    }

    private func wattString(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f W", value)
        }
        return String(format: "%.2f W", value)
    }

    private var accessibilityText: String {
        switch topology {
        case .adapterToMac:
            return "Power flow from adapter to Mac, \(wattString(snapshot.systemLoadWatts ?? snapshot.adapterInputWatts ?? 0))"
        case .batteryToMac:
            return "Power flow from battery to Mac, \(wattString(snapshot.batteryDischargeWatts ?? snapshot.systemLoadWatts ?? 0))"
        case .adapterAndBatteryToMac:
            return "Adapter and battery are both powering the Mac"
        case .adapterToMacAndBattery:
            return "Adapter power is split between the Mac and battery charging"
        case .unavailable:
            return "Power flow unavailable"
        }
    }
}

private enum FlowTopology {
    case adapterToMac
    case batteryToMac
    case adapterAndBatteryToMac
    case adapterToMacAndBattery
    case unavailable
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
