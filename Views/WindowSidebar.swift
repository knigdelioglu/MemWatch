import SwiftUI

enum WindowNavigationSelection: Equatable {
    case overview
    case cleanup
    case displays
    case settings
}

struct WindowSidebar: View {
    let selection: WindowNavigationSelection
    let onOpenOverview: () -> Void
    let onOpenCleanup: () -> Void
    let onOpenDisplays: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("MemWatch").font(.subheadline.weight(.semibold))
                    Text("A cleaner, healthier Mac").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            navigationButton("Overview", symbol: "waveform.path.ecg", active: selection == .overview, action: onOpenOverview)
            navigationButton("Cleanup", symbol: "sparkles", active: selection == .cleanup, action: onOpenCleanup)
            navigationButton("Displays & Awake", symbol: "display", active: selection == .displays, action: onOpenDisplays)
            navigationButton("Settings", symbol: "gearshape", active: selection == .settings, action: onOpenSettings)

            Spacer(minLength: 16)

            Label("MemWatch Pro", systemImage: "crown.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("MemWatch Pro is not available in this build")
        }
        .padding(13)
        .frame(width: 154)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) { Divider() }
    }

    private func navigationButton(
        _ title: String,
        symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if active {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                    .padding(.horizontal, 8)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityAddTraits(.isSelected)
            } else {
                Button(action: action) {
                    Label(title, systemImage: symbol)
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                        .padding(.horizontal, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
    }
}
