import SwiftUI

struct CleanupView: View {
    @ObservedObject var service: MoleCleanupService
    @State private var pendingAction: MoleCleanupAction?
    @State private var administratorPassword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cleanup")
                        .font(.title2.weight(.semibold))
                    Text("Run Mole's cleanup command from MemWatch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                status

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            start(.preview)
                        } label: {
                            Label("Preview (dry run)", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(service.isRunning || service.commandPath == nil)
                        .accessibilityHint("Runs mo clean --dry-run; nothing is deleted")

                        Button {
                            start(.clean)
                        } label: {
                            Label("Run Mole cleanup", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(service.isRunning || service.commandPath == nil)
                        .accessibilityHint("Runs the installed Mole CLI's mo clean command without opening Terminal")

                        if service.isRunning {
                            Button(role: .cancel) {
                                service.cancel()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Toggle(isOn: $service.includeSystemCleanup) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include system cleanup (administrator password)")
                                .font(.callout)
                            Text("MemWatch asks for your administrator password before Mole starts. It is passed to sudo once, never saved, and the sudo permission is revoked when Mole finishes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(service.isRunning)

                    if let commandPath = service.commandPath {
                        Text("Using \(commandPath)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }

                    Text("Mole manages the cleanup rules. Without an active administrator session, it skips system caches and continues with user-level cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !service.output.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Mole output")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let lastRunAt = service.lastRunAt {
                                Text(lastRunAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        ScrollView([.horizontal, .vertical]) {
                            Text(service.output)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(minHeight: 120, maxHeight: 360)
                        .background(
                            Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .accessibilityLabel("Mole cleanup command output")
                    }
                }

                Link("Mole on GitHub", destination: URL(string: "https://github.com/tw93/Mole")!)
                    .font(.caption)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .sheet(isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { cancelPasswordPrompt() } }
        )) {
            passwordSheet
        }
        .onAppear {
            // Opening the page must never delete anything by itself; only
            // re-check whether Mole is installed.
            service.refreshAvailability()
        }
    }

    @ViewBuilder
    private var status: some View {
        switch service.phase {
        case .ready:
            statusRow("Mole is ready", symbol: "checkmark.circle.fill", color: .green)
        case .unavailable:
            VStack(alignment: .leading, spacing: 6) {
                statusRow("Mole CLI was not found", symbol: "exclamationmark.triangle.fill", color: .orange)
                Text("Install Mole with Homebrew by running: brew install mole")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Check again") {
                    service.refreshAvailability()
                }
                .font(.caption)
                Link("Open Mole's installation instructions", destination: URL(string: "https://github.com/tw93/Mole#quick-start")!)
                    .font(.caption)
            }
        case .running(let action):
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text(action == .preview
                    ? "Mole preview is running (nothing will be deleted)…"
                    : "Mole cleanup is running in the background…")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityElement(children: .combine)
        case .cancelled(let action):
            statusRow("Mole \(action.displayName.lowercased()) was stopped", symbol: "stop.circle.fill", color: .orange)
        case .finished(let action, let exitStatus):
            VStack(alignment: .leading, spacing: 4) {
                statusRow(
                    exitStatus == 0
                        ? "Mole \(action.displayName.lowercased()) finished"
                        : "Mole exited with status \(exitStatus)",
                    symbol: exitStatus == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: exitStatus == 0 ? .green : .orange
                )
                if exitStatus == 0 {
                    Text("Review Mole's output for items it cleaned or skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(_, let message):
            VStack(alignment: .leading, spacing: 4) {
                statusRow("Mole could not be started", symbol: "xmark.circle.fill", color: .red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func start(_ action: MoleCleanupAction) {
        if service.needsAdministratorPassword {
            administratorPassword = ""
            pendingAction = action
        } else {
            service.run(action)
        }
    }

    private func confirmPassword() {
        guard let action = pendingAction, !administratorPassword.isEmpty else { return }
        let password = administratorPassword
        administratorPassword = ""
        pendingAction = nil
        service.run(action, administratorPassword: password)
    }

    private func cancelPasswordPrompt() {
        administratorPassword = ""
        pendingAction = nil
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Yönetici izni gerekli", systemImage: "lock.shield")
                .font(.headline)

            Text(pendingAction == .preview
                ? "Mole önizlemesinin sistem önbelleklerini de görebilmesi için Mac yönetici parolanı gir."
                : "Mole'un sistem önbelleklerini de temizleyebilmesi için Mac yönetici parolanı gir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Parola", text: $administratorPassword)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirmPassword)

            Text("Parola yalnızca bu çalıştırma için sudo'ya iletilir; diske veya ayarlara kaydedilmez.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Parolasız devam et") {
                    let action = pendingAction
                    cancelPasswordPrompt()
                    if let action {
                        service.run(action)
                    }
                }
                .help("Yalnızca kullanıcı düzeyinde temizlik yapılır")

                Spacer()

                Button("İptal", role: .cancel) {
                    cancelPasswordPrompt()
                }
                .keyboardShortcut(.cancelAction)

                Button("Devam") {
                    confirmPassword()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(administratorPassword.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func statusRow(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}
