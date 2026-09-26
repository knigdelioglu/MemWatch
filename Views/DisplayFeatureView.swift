import SwiftUI

struct DisplayFeatureView: View {
    @ObservedObject var display: DisplayCoordinator
    @ObservedObject private var connectionController: DisplayConnectionController

    let onBack: () -> Void
    var showsNavigation = false
    var onOpenOverview: () -> Void = {}
    var onOpenCleanup: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    @State private var showingDiagnostics = false
    @State private var showingMoreDetails = false
    @State private var brightnessDraft: Double = 0
    @State private var isAdjustingBrightness = false
    @State private var volumeDraft: Double = 0
    @State private var isAdjustingVolume = false

    init(
        display: DisplayCoordinator,
        onBack: @escaping () -> Void = {},
        showsNavigation: Bool = false,
        onOpenOverview: @escaping () -> Void = {},
        onOpenCleanup: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.display = display
        self.onBack = onBack
        self.showsNavigation = showsNavigation
        self.onOpenOverview = onOpenOverview
        self.onOpenCleanup = onOpenCleanup
        self.onOpenSettings = onOpenSettings
        _connectionController = ObservedObject(wrappedValue: display.displayConnectionController)
    }

    var body: some View {
        Group {
            if showsNavigation {
                HStack(spacing: 0) {
                    WindowSidebar(
                        selection: .displays,
                        onOpenOverview: onOpenOverview,
                        onOpenCleanup: onOpenCleanup,
                        onOpenDisplays: {},
                        onOpenSettings: onOpenSettings
                    )
                    controlPanel
                }
            } else {
                controlPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: showsNavigation ? 520 : 390, minHeight: showsNavigation ? 720 : 860)
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

    private var controlPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    if showsNavigation {
                        windowControlCards
                    } else {
                        popoverControlCards
                    }
                }
                .padding(showsNavigation ? 12 : 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var windowControlCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            externalDisplayWindowCard
            builtInDisplayWindowCard
            keepAwakeCard

            DisclosureGroup("Connection & diagnostics", isExpanded: $showingMoreDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    connectionCard
                    diagnosticsCard
                }
                .padding(.top, 8)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 2)
        }
    }

    private var popoverControlCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            displayStatusCard
            brightnessCard
            volumeCard
            keepAwakeCard
            hiDPICard
            connectionCard
            diagnosticsCard
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !showsNavigation {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                }
                .buttonStyle(.plain)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHint("Returns to the MemWatch overview")
            }

            Label(showsNavigation ? "Displays & Awake" : "Display", systemImage: "sun.max.fill")
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
                    Text("External Display")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(display.currentDisplayLabel)
                        .font(.subheadline.weight(.semibold))

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

            HStack(spacing: 9) {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(display.capabilities.internalBrightness.isAvailable ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Built-in Display")
                        .font(.caption.weight(.semibold))
                    if display.capabilities.internalBrightness.isAvailable {
                        if let brightness = display.currentInternalBrightness {
                            Text("Brightness \(brightness)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Brightness unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(display.capabilities.internalBrightness.reason ?? "Not available on this Mac")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if display.capabilities.internalBrightness.isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Built-in display available")
                }
            }

            Divider()

            HStack(spacing: 12) {
                statusMetric(title: "Ambient", value: luxText)
                statusMetric(title: "Brightness", value: display.brightnessControlText)
                statusMetric(title: "HiDPI", value: display.isHiDPIActive ? "On" : "Off")
            }
        }
    }

    private var externalDisplayWindowCard: some View {
        FeatureCard {
            HStack(spacing: 10) {
                Image(systemName: display.currentDisplayInfo == nil ? "display.trianglebadge.exclamationmark" : "display")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(display.currentDisplayInfo == nil ? .orange : .blue)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.currentDisplayLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(displayStatusHeadline)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Label(
                    display.currentDisplayInfo == nil ? "Unavailable" : "Connected",
                    systemImage: display.currentDisplayInfo == nil ? "minus.circle" : "checkmark.circle.fill"
                )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(display.currentDisplayInfo == nil ? .secondary : .green)
            }

            Divider()

            featureHeader(title: "Brightness", symbol: "sun.max.fill")
            externalBrightnessControl
            automaticBrightnessControl

            Divider()

            volumeControl

            Divider()

            retinaModeControl
        }
    }

    private var builtInDisplayWindowCard: some View {
        FeatureCard {
            featureHeader(title: "Built-in Display", symbol: "laptopcomputer")
            internalBrightnessControl
        }
    }

    @ViewBuilder
    private var internalBrightnessControl: some View {
        if display.capabilities.internalBrightness.isAvailable,
           let brightness = display.currentInternalBrightness {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Brightness")
                    Spacer()
                    Text("\(brightness)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .font(.caption)

                Slider(
                    value: Binding(
                        get: { Double(display.currentInternalBrightness ?? brightness) },
                        set: { _ = display.setInternalBrightness(Int($0.rounded())) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .accessibilityLabel("Built-in display brightness")
            }
        } else {
            capabilityMessage(display.capabilities.internalBrightness)
        }
    }

    @ViewBuilder
    private var externalBrightnessControl: some View {
        if display.capabilities.ddc.isAvailable, display.currentDisplayInfo != nil {
            VStack(alignment: .leading, spacing: 5) {
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
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .disabled(display.currentDisplayInfo == nil)
        } else {
            capabilityMessage(display.capabilities.ddc)
        }
    }

    private var automaticBrightnessControl: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(
                "Auto-brightness (ambient light)",
                isOn: Binding(
                    get: { display.autoBrightnessEnabled },
                    set: { display.setAutoBrightnessEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!canUseAutomaticBrightness)

            if !canUseAutomaticBrightness {
                Text(automaticBrightnessReason)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            featureHeader(title: "Volume", symbol: "speaker.wave.2.fill")

            HStack(spacing: 8) {
                Image(systemName: display.monitorVolumeControlValue == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { volumeDraft },
                        set: { newValue in scheduleVolumeWrite(newValue) }
                    ),
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { isAdjustingVolume = $0 }
                )
                .accessibilityLabel("External display volume")

                Text(volumeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 34, alignment: .trailing)

                Button {
                    display.toggleMuteForSettingsSync()
                } label: {
                    Label("Mute", systemImage: "speaker.slash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Mute or unmute external display")
                .accessibilityLabel(display.monitorVolumeControlValue == 0 ? "Unmute external display" : "Mute external display")
            }
            .disabled(!display.capabilities.volume.isAvailable || display.currentDisplayInfo == nil)

            if !display.capabilities.volume.isAvailable || display.currentDisplayInfo == nil {
                capabilityMessage(display.capabilities.volume)
            }
        }
    }

    private var retinaModeControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "HiDPI / Retina Mode",
                isOn: Binding(
                    get: { display.isHiDPIActive },
                    set: { enabled in
                        if enabled {
                            display.applyRetinaMode()
                        } else {
                            display.disableRetinaMode()
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!display.capabilities.hiDPI.isAvailable || display.currentDisplayInfo == nil)

            Text(display.hiDPIStatusText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !display.capabilities.hiDPI.isAvailable || display.currentDisplayInfo == nil {
                capabilityMessage(display.capabilities.hiDPI)
            }
        }
    }

    private var brightnessCard: some View {
        FeatureCard {
            featureHeader(title: "Brightness", symbol: "sun.max.fill")
            internalBrightnessControl

            Divider()
            externalBrightnessControl
            automaticBrightnessControl
        }
    }

    private var volumeCard: some View {
        FeatureCard {
            volumeControl
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
            : display.brightnessControlText
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
    @State private var selectedDuration = "never"
    @State private var selectedKeepsDisplayAwake = true

    init(display: DisplayCoordinator, compact: Bool = false) {
        self.display = display
        self.compact = compact
        _selectedKeepsDisplayAwake = State(initialValue: display.keepAwakeState.keepDisplayAwake)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Label("Keep Awake", systemImage: "moon.zzz.fill")
                .font(compact ? .headline : .subheadline.weight(.semibold))

            HStack(spacing: 7) {
                awakeModeButton(
                    title: "System & Displays",
                    symbol: "laptopcomputer.and.iphone",
                    keepsDisplayAwake: true
                )
                awakeModeButton(
                    title: "System Only",
                    symbol: "laptopcomputer",
                    keepsDisplayAwake: false
                )
            }

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

            HStack(spacing: 6) {
                durationButton(title: "5 minutes", mode: "5")
                durationButton(title: "15 minutes", mode: "15")
                durationButton(title: "1 hour", mode: "60")
                durationButton(title: "Indefinitely", mode: "never")
            }

            Button {
                display.setKeepAwakeFeatureEnabled(true)
                display.setKeepAwakeDisplayAwake(selectedKeepsDisplayAwake)
                if selectedDuration == "5" {
                    display.startSessionWithCustomMinutes(5)
                } else {
                    display.startSessionWithDurationMode(selectedDuration)
                }
            } label: {
                Label("Start Keeping Awake", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if display.keepAwakeState.featureEnabled {
                Button("Stop Keeping Awake") {
                    display.setKeepAwakeFeatureEnabled(false)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func awakeModeButton(title: String, symbol: String, keepsDisplayAwake: Bool) -> some View {
        let selected = selectedKeepsDisplayAwake == keepsDisplayAwake
        return Button {
            selectedKeepsDisplayAwake = keepsDisplayAwake
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: compact ? 34 : 38)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func durationButton(title: String, mode: String) -> some View {
        Button {
            selectedDuration = mode
        } label: {
            Text(title)
                .font(.system(size: compact ? 8 : 9, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 28)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.bordered)
        .tint(selectedDuration == mode ? .accentColor : .secondary)
        .accessibilityAddTraits(selectedDuration == mode ? .isSelected : [])
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
