import SwiftUI

struct DisplayFeatureView: View {
    @ObservedObject var display: DisplayCoordinator
    @ObservedObject private var connectionController: DisplayConnectionController

    let onBack: () -> Void
    @State private var showingDiagnostics = false
    @State private var brightnessDraft: Double = 0
    @State private var isAdjustingBrightness = false
    @State private var volumeDraft: Double = 0
    @State private var isAdjustingVolume = false

    init(display: DisplayCoordinator, onBack: @escaping () -> Void = {}) {
        self.display = display
        self.onBack = onBack
        _connectionController = ObservedObject(wrappedValue: display.displayConnectionController)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    displayStatusCard
                    brightnessCard
                    volumeCard
                    keepAwakeCard
                    hiDPICard
                    connectionCard
                    diagnosticsCard
                }
                .padding(16)
            }
        }
        .frame(width: 430, height: 640)
        .onAppear {
            brightnessDraft = Double(display.monitorBrightnessControlValue)
            volumeDraft = Double(display.monitorVolumeControlValue)
        }
        .onChange(of: display.monitorBrightnessControlValue) { newValue in
            if ExternalSliderInteractionPolicy.shouldSynchronizeFromBackend(isAdjusting: isAdjustingBrightness) {
                brightnessDraft = Double(newValue)
            }
        }
        .onChange(of: display.monitorVolumeControlValue) { newValue in
            if ExternalSliderInteractionPolicy.shouldSynchronizeFromBackend(isAdjusting: isAdjustingVolume) {
                volumeDraft = Double(newValue)
            }
        }
        .onDisappear {
            if isAdjustingBrightness {
                display.endManualBrightnessInteraction()
            }
            display.cancelPendingManualBrightnessWrite()
            display.cancelPendingManualVolumeWrite()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHint("Returns to the MemWatch overview")

            Label("Display", systemImage: "sun.max.fill")
                .font(.headline)

            Spacer()

            Button {
                display.refreshDisplay()
            } label: {
                Label("Refresh display", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Refresh display state")
            .accessibilityLabel("Refresh display state")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var displayStatusCard: some View {
        FeatureCard {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: display.currentDisplayInfo == nil ? "display.trianglebadge.exclamationmark" : "display")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(display.currentDisplayInfo == nil ? .orange : .green)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(display.currentDisplayLabel)
                        .font(.headline)

                    Text(displayStatusHeadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let reason = display.capabilities.externalDisplay.reason, display.currentDisplayInfo == nil {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 12) {
                statusMetric(title: "Ambient", value: luxText)
                statusMetric(title: "Brightness", value: display.brightnessActualText)
                statusMetric(title: "HiDPI", value: display.isHiDPIActive ? "On" : "Off")
            }
        }
    }

    private var brightnessCard: some View {
        FeatureCard {
            featureHeader(title: "Brightness", symbol: "sun.max.fill")

            if display.capabilities.internalBrightness.isAvailable, display.currentInternalBrightness != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Mac display")
                        Spacer()
                        Text("\(display.currentInternalBrightness ?? 0)%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .font(.caption)

                    Slider(
                        value: Binding(
                            get: { Double(display.currentInternalBrightness ?? 0) },
                            set: { _ = display.setInternalBrightness(Int($0.rounded())) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                    .accessibilityLabel("Mac display brightness")
                }
            } else {
                capabilityMessage(display.capabilities.internalBrightness)
            }

            Divider()

            if display.capabilities.ddc.isAvailable, display.currentDisplayInfo != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("External display")
                        Spacer()
                        Text(externalBrightnessText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .font(.caption)

                    Slider(
                        value: Binding(
                            get: { brightnessDraft },
                            set: { newValue in scheduleBrightnessWrite(newValue) }
                        ),
                        in: 0...100,
                        step: 1,
                        onEditingChanged: handleBrightnessEditingChanged
                    )
                    .accessibilityLabel("External display brightness")

                    Text(display.brightnessDiagnosticInlineText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                capabilityMessage(display.capabilities.ddc)
            }

            Toggle(
                "Automatic external brightness",
                isOn: Binding(
                    get: { display.autoBrightnessEnabled },
                    set: { display.setAutoBrightnessEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .disabled(!canUseAutomaticBrightness)

            if !canUseAutomaticBrightness {
                Text(automaticBrightnessReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var volumeCard: some View {
        FeatureCard {
            featureHeader(title: "Monitor volume", symbol: "speaker.wave.2.fill")

            HStack(spacing: 10) {
                Image(systemName: display.monitorVolumeControlValue == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { volumeDraft },
                        set: { newValue in scheduleVolumeWrite(newValue) }
                    ),
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { isEditing in
                        isAdjustingVolume = isEditing
                    }
                )
                .accessibilityLabel("External display volume")

                Text(volumeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 40, alignment: .trailing)

                Button {
                    display.toggleMuteForSettingsSync()
                } label: {
                    Label("Mute", systemImage: "speaker.slash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Mute or unmute external display")
                .accessibilityLabel(display.monitorVolumeControlValue == 0 ? "Unmute external display" : "Mute external display")
            }
            .disabled(!display.capabilities.volume.isAvailable || display.currentDisplayInfo == nil)

            if !display.capabilities.volume.isAvailable || display.currentDisplayInfo == nil {
                capabilityMessage(display.capabilities.volume)
            }
        }
    }

    private var keepAwakeCard: some View {
        FeatureCard {
            KeepAwakeControlsView(display: display)
        }
    }

    private var hiDPICard: some View {
        FeatureCard {
            featureHeader(title: "HiDPI", symbol: "rectangle.inset.filled.and.person.filled")

            Text(display.hiDPIStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Apply Retina mode") {
                    display.applyRetinaMode()
                }
                .buttonStyle(.borderedProminent)

                Button("Disable") {
                    display.disableRetinaMode()
                }
                .buttonStyle(.bordered)
            }
            .disabled(!display.capabilities.hiDPI.isAvailable || display.currentDisplayInfo == nil)

            if !display.capabilities.hiDPI.isAvailable || display.currentDisplayInfo == nil {
                capabilityMessage(display.capabilities.hiDPI)
            }
        }
    }

    private var connectionCard: some View {
        FeatureCard {
            featureHeader(title: "Display connection", symbol: "rectangle.connected.to.line.below")

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: connectionSymbol)
                    .foregroundStyle(connectionColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(connectionTitle)
                        .font(.caption.weight(.semibold))
                    Text(connectionController.snapshot.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Button(connectionController.snapshot.phase == .connected ? "Disconnect in software" : "Reconnect display") {
                display.toggleExternalDisplayConnection()
            }
            .buttonStyle(.bordered)
            .disabled(!display.capabilities.softwareDisconnect.isAvailable || !connectionController.snapshot.canToggle)

            if !display.capabilities.softwareDisconnect.isAvailable || !connectionController.snapshot.canToggle {
                capabilityMessage(display.capabilities.softwareDisconnect)
            }
        }
    }

    private var diagnosticsCard: some View {
        FeatureCard {
            DisclosureGroup("Diagnostics", isExpanded: $showingDiagnostics) {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticButton("Read EDID", action: display.readEDIDDiagnostic)
                    diagnosticButton("Read HDR brightness", action: display.readHDRBrightnessDiagnostic)
                    diagnosticButton("Read DDC brightness max", action: display.readDDCBrightnessMaxDiagnostic)
                    diagnosticButton("Probe DDC raw brightness", action: display.readDDCRawBrightnessProbeDiagnostic)
                    diagnosticButton("Run brightness mapping", action: display.readBrightnessMappingDiagnostic)

                    Text(display.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let summary = display.currentEDIDSummary {
                        diagnosticValue(title: "EDID", value: String(describing: summary))
                    }
                    if let summary = display.ddcBrightnessMaxDiagnosticSummary {
                        diagnosticValue(title: "DDC max", value: String(describing: summary))
                    }
                    if let summary = display.ddcRawBrightnessProbeSummary {
                        diagnosticValue(title: "DDC raw", value: String(describing: summary))
                    }
                    if let summary = display.brightnessMappingDiagnosticSummary {
                        diagnosticValue(title: "Mapping", value: String(describing: summary))
                    }
                }
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private func featureHeader(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
    }

    private func statusMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capabilityMessage(_ capability: DisplayCapability) -> some View {
        Text(capability.reason ?? "This capability is unavailable on the current Mac.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func diagnosticButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .font(.caption)
    }

    private func diagnosticValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayStatusHeadline: String {
        if display.currentDisplayInfo != nil {
            return display.autoBrightnessEnabled ? "Automatic brightness is active" : "Manual brightness is active"
        }
        return display.capabilities.externalDisplay.reason ?? "Waiting for a supported external display"
    }

    private var externalBrightnessText: String {
        isAdjustingBrightness
            ? "\(Int(brightnessDraft.rounded()))%"
            : display.brightnessActualText
    }

    private var volumeText: String {
        isAdjustingVolume
            ? "\(Int(volumeDraft.rounded()))%"
            : "\(display.monitorVolumeControlValue)%"
    }

    private func scheduleBrightnessWrite(_ newValue: Double) {
        let intValue = ExternalSliderInteractionPolicy.roundedValue(newValue)
        let changed = ExternalSliderInteractionPolicy.shouldSchedule(
            newValue: newValue,
            previousDraft: brightnessDraft
        )
        brightnessDraft = newValue
        guard changed else { return }

        display.scheduleMonitorBrightnessWrite(intValue)
    }

    private func handleBrightnessEditingChanged(_ isEditing: Bool) {
        if isEditing {
            display.beginManualBrightnessInteraction()
        } else {
            display.endManualBrightnessInteraction()
        }
        isAdjustingBrightness = isEditing
    }

    private func scheduleVolumeWrite(_ newValue: Double) {
        let intValue = ExternalSliderInteractionPolicy.roundedValue(newValue)
        let changed = ExternalSliderInteractionPolicy.shouldSchedule(
            newValue: newValue,
            previousDraft: volumeDraft
        )
        volumeDraft = newValue
        guard changed else { return }

        display.scheduleMonitorVolumeWrite(intValue)
    }

    private var luxText: String {
        guard let lux = display.currentLux else { return "—" }
        return "\(Int(lux.rounded())) lx"
    }

    private var canUseAutomaticBrightness: Bool {
        display.currentDisplayInfo != nil &&
            display.capabilities.ambientLightSensor.isAvailable &&
            display.capabilities.ddc.isAvailable
    }

    private var automaticBrightnessReason: String {
        if !display.capabilities.ambientLightSensor.isAvailable {
            return display.capabilities.ambientLightSensor.reason ?? "Ambient light sensor is unavailable."
        }
        if !display.capabilities.ddc.isAvailable {
            return display.capabilities.ddc.reason ?? "DDC brightness control is unavailable."
        }
        return display.capabilities.externalDisplay.reason ?? "Connect a supported external display to enable automatic brightness."
    }

    private var connectionTitle: String {
        switch connectionController.snapshot.phase {
        case .connected: return "Connected"
        case .softwareDisconnected: return "Disconnected by MemWatch"
        case .physicallyDisconnected: return "Not connected"
        case .disconnecting: return "Disconnecting"
        case .reconnecting: return "Reconnecting"
        case .unsupported: return "Unsupported"
        case .failed: return "Connection check failed"
        }
    }

    private var connectionSymbol: String {
        switch connectionController.snapshot.phase {
        case .connected: return "checkmark.circle.fill"
        case .reconnecting, .disconnecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "rectangle.slash"
        }
    }

    private var connectionColor: Color {
        switch connectionController.snapshot.phase {
        case .connected: return .green
        case .failed: return .red
        case .reconnecting, .disconnecting: return .orange
        default: return .secondary
        }
    }
}

/// The keep-awake feature is available from the main overview and the display
/// details route. Keeping the controls in one view prevents those entry points
/// from drifting apart while the coordinator remains the single state owner.
struct KeepAwakeControlsView: View {
    @ObservedObject var display: DisplayCoordinator
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Label("Keep Awake", systemImage: "moon.zzz.fill")
                .font(compact ? .headline : .subheadline.weight(.semibold))

            Toggle(
                "Keep system awake",
                isOn: Binding(
                    get: { display.keepAwakeState.featureEnabled },
                    set: { display.setKeepAwakeFeatureEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .font(compact ? .body : .subheadline)

            Toggle(
                "Keep display awake",
                isOn: Binding(
                    get: { display.keepAwakeState.keepDisplayAwake },
                    set: { display.setKeepAwakeDisplayAwake($0) }
                )
            )
            .disabled(!display.keepAwakeState.featureEnabled)
            .font(compact ? .body : .subheadline)

            Toggle(
                "Only while connected to power",
                isOn: Binding(
                    get: { display.keepAwakeState.onlyWhilePluggedIn },
                    set: { display.setKeepAwakePluggedOnly($0) }
                )
            )
            .disabled(!display.keepAwakeState.featureEnabled)
            .font(compact ? .body : .subheadline)

            HStack {
                Text(display.keepAwakeSummaryText)
                    .font(compact ? .callout : .caption)
                    .foregroundStyle(display.isAwakeAssertionActive ? .green : .secondary)
                Spacer()
                if let until = display.keepAwakeUntilText {
                    Text(until)
                        .font((compact ? Font.callout : Font.caption).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                sessionButton(title: "15 min", mode: "15")
                sessionButton(title: "30 min", mode: "30")
                sessionButton(title: "1 hour", mode: "60")
                sessionButton(title: "Until off", mode: "never")
            }
        }
    }

    private func sessionButton(title: String, mode: String) -> some View {
        Button(title) {
            display.startSessionWithDurationMode(mode)
        }
        .buttonStyle(.bordered)
        .font(compact ? .callout : .caption)
        .frame(maxWidth: .infinity)
        .controlSize(compact ? .small : .regular)
        .disabled(!display.keepAwakeState.featureEnabled)
    }
}

private struct FeatureCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
