import SwiftUI

struct UnifiedSettingsView: View {
    @ObservedObject var monitor: MonitoringService
    @ObservedObject var display: DisplayCoordinator
    @State private var brightnessDraft: Double = 0
    @State private var isAdjustingBrightness = false
    @State private var brightnessTask: Task<Void, Never>?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            systemTab
                .tabItem { Label("System", systemImage: "gauge.with.dots.needle.50percent") }

            displayTab
                .tabItem { Label("Display", systemImage: "sun.max.fill") }

            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(minWidth: 680, minHeight: 520)
        .padding(20)
        .onAppear {
            brightnessDraft = Double(display.monitorBrightnessControlValue)
        }
        .onChange(of: display.monitorBrightnessControlValue) { newValue in
            if ExternalSliderInteractionPolicy.shouldSynchronizeFromBackend(isAdjusting: isAdjustingBrightness) {
                brightnessDraft = Double(newValue)
            }
        }
        .onDisappear {
            brightnessTask?.cancel()
            if isAdjustingBrightness {
                display.endManualBrightnessInteraction()
            }
        }
    }

    private var systemTab: some View {
        Form {
            Section("System health") {
                LabeledContent("Memory", value: "\(monitor.snapshot.usagePercent)% used")
                LabeledContent("Memory pressure", value: monitor.pressure.displayName)
                LabeledContent("Thermal state", value: monitor.diagnostics.thermalState.displayName)
                LabeledContent("Storage", value: monitor.hasStorageWarning ? "Needs attention" : "Normal")
                LabeledContent("Energy source", value: monitor.powerSnapshot.source.displayName)
            }

            Section("Monitoring") {
                Text("System health is sampled by the shared MemWatch scheduler. Display polling and expensive process snapshots remain independently bounded by their owning feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Refresh system health") {
                    monitor.refresh(forceStorage: true, forceDiagnostics: true)
                }
            }

            Section("Cleanup") {
                Text("Cleanup & Storage remains available from the main MemWatch popover and context menu. Its privileged helper boundary is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch MemWatch at login",
                    isOn: Binding(
                        get: { monitor.launchAtLoginState == .enabled },
                        set: { monitor.setLaunchAtLogin($0) }
                    )
                )

                HStack {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(monitor.launchAtLoginState.displayName)
                        .foregroundStyle(monitor.launchAtLoginState == .enabled ? .green : .secondary)
                }
                .font(.caption)

                if let error = monitor.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if monitor.launchAtLoginState == .requiresApproval || monitor.launchAtLoginState == .needsSetup {
                    Button("Open Login Items Settings") {
                        monitor.openLoginItemsSettings()
                    }
                }
            }

            Section("Notifications") {
                Toggle(
                    "Smart alerts",
                    isOn: Binding(
                        get: { monitor.notificationsEnabled },
                        set: { monitor.setNotificationsEnabled($0) }
                    )
                )

                HStack {
                    Text("Permission")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(monitor.notificationAuthorization.displayName)
                }
                .font(.caption)

                if monitor.notificationAuthorization == .denied {
                    Button("Open Notification Settings") {
                        monitor.openNotificationSettings()
                    }
                }
            }

            Section("About") {
                LabeledContent("Application", value: "MemWatch")
                LabeledContent("Display feature", value: "AmbientSync integrated")
                Text("MemWatch owns the single menu-bar lifecycle, scheduler and status item. Display controls remain optional and report their capability state when hardware or macOS APIs are unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var displayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsDisplaySummary
                settingsBrightnessSection
                settingsKeepAwakeSection
                settingsHiDPISection
                settingsConnectionSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsDisplaySummary: some View {
        SettingsSectionCard {
            Label("Display", systemImage: "sun.max.fill")
                .font(.headline)

            Text(display.currentDisplayLabel)
                .font(.title3.weight(.semibold))

            Text(display.currentDisplayInfo == nil
                 ? (display.capabilities.externalDisplay.reason ?? "No supported external display is connected.")
                 : display.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsBrightnessSection: some View {
        SettingsSectionCard {
            Text("Brightness")
                .font(.headline)

            Toggle(
                "Automatic external brightness",
                isOn: Binding(
                    get: { display.autoBrightnessEnabled },
                    set: { display.setAutoBrightnessEnabled($0) }
                )
            )
            .disabled(!canUseAutomaticBrightness)

            if !canUseAutomaticBrightness {
                Text(automaticBrightnessReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if display.currentDisplayInfo != nil, display.capabilities.ddc.isAvailable {
                HStack {
                    Text("External display")
                    Spacer()
                    Text(settingsExternalBrightnessText)
                        .font(.caption.monospacedDigit())
                }
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
            }

            if display.capabilities.internalBrightness.isAvailable, display.currentInternalBrightness != nil {
                HStack {
                    Text("Mac display")
                    Spacer()
                    Text("\(display.currentInternalBrightness ?? 0)%")
                        .font(.caption.monospacedDigit())
                }
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
        }
    }

    private var settingsKeepAwakeSection: some View {
        SettingsSectionCard {
            KeepAwakeControlsView(display: display)
        }
    }

    private var settingsHiDPISection: some View {
        SettingsSectionCard {
            Text("HiDPI")
                .font(.headline)
            Text(display.hiDPIStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Apply Retina mode") { display.applyRetinaMode() }
                    .buttonStyle(.borderedProminent)
                Button("Disable") { display.disableRetinaMode() }
                    .buttonStyle(.bordered)
            }
            .disabled(!display.capabilities.hiDPI.isAvailable || display.currentDisplayInfo == nil)

            if !display.capabilities.hiDPI.isAvailable {
                Text(display.capabilities.hiDPI.reason ?? "HiDPI is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var settingsConnectionSection: some View {
        SettingsSectionCard {
            Text("Display connection")
                .font(.headline)
            Text(display.displayConnectionController.snapshot.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(display.displayConnectionController.snapshot.phase == .connected ? "Disconnect in software" : "Reconnect display") {
                display.toggleExternalDisplayConnection()
            }
            .disabled(!display.capabilities.softwareDisconnect.isAvailable || !display.displayConnectionController.snapshot.canToggle)
        }
    }

    private var diagnosticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionCard {
                    Text("Display diagnostics")
                        .font(.headline)
                    diagnosticButton("Read EDID", action: display.readEDIDDiagnostic)
                    diagnosticButton("Read HDR brightness", action: display.readHDRBrightnessDiagnostic)
                    diagnosticButton("Read DDC brightness max", action: display.readDDCBrightnessMaxDiagnostic)
                    diagnosticButton("Probe DDC raw brightness", action: display.readDDCRawBrightnessProbeDiagnostic)
                    diagnosticButton("Run brightness mapping", action: display.readBrightnessMappingDiagnostic)
                }

                SettingsSectionCard {
                    Text("Current state")
                        .font(.headline)
                    Text(display.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(display.brightnessDiagnosticInlineText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(display.cgsManualModeSwitcherStatusText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnosticButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private var settingsExternalBrightnessText: String {
        isAdjustingBrightness
            ? "\(Int(brightnessDraft.rounded()))%"
            : display.brightnessActualText
    }

    private func scheduleBrightnessWrite(_ newValue: Double) {
        let intValue = ExternalSliderInteractionPolicy.roundedValue(newValue)
        let changed = ExternalSliderInteractionPolicy.shouldSchedule(
            newValue: newValue,
            previousDraft: brightnessDraft
        )
        brightnessDraft = newValue
        guard changed else { return }

        brightnessTask?.cancel()
        brightnessTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ExternalSliderInteractionPolicy.brightnessDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            display.setMonitorBrightness(intValue)
        }
    }

    private func handleBrightnessEditingChanged(_ isEditing: Bool) {
        if isEditing {
            display.beginManualBrightnessInteraction()
        } else {
            display.endManualBrightnessInteraction()
        }
        isAdjustingBrightness = isEditing
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
}

private struct SettingsSectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
