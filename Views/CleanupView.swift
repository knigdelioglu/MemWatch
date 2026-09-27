import SwiftUI

struct CleanupView: View {
    @ObservedObject var service: MoleCleanupService

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
                    Button(action: service.runCleanup) {
                        if service.isRunning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Run Mole cleanup", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isRunning || service.commandPath == nil)
                    .accessibilityHint("Runs the installed Mole CLI's mo clean command without opening Terminal")

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
        .onAppear(perform: service.runCleanup)
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
                Link("Open Mole's installation instructions", destination: URL(string: "https://github.com/tw93/Mole#quick-start")!)
                    .font(.caption)
            }
        case .running:
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Mole cleanup is running in the background…")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityElement(children: .combine)
        case .finished(_, let exitStatus):
            VStack(alignment: .leading, spacing: 4) {
                statusRow(
                    exitStatus == 0 ? "Mole finished (exit status 0)" : "Mole exited with status \(exitStatus)",
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

    private func statusRow(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}
