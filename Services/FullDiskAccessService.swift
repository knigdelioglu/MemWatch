import AppKit
import Foundation

enum FullDiskAccessState: String, Sendable {
    case granted
    case denied
    case unknown

    var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .unknown: return "Unknown"
        }
    }
}

@MainActor
final class FullDiskAccessService: ObservableObject {
    @Published private(set) var state: FullDiskAccessState = .unknown

    init() {
        refresh()
    }

    var isAvailable: Bool { state == .granted }

    func refresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [
            home.appendingPathComponent("Library/Safari/History.db"),
            home.appendingPathComponent("Library/Mail", isDirectory: true)
        ]

        var sawExistingProbe = false
        for probe in probes where FileManager.default.fileExists(atPath: probe.path) {
            sawExistingProbe = true
            if canOpen(probe) {
                state = .granted
                return
            }
        }

        state = sawExistingProbe ? .denied : .unknown
    }

    func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func canOpen(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            do {
                _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).prefix(1)
                return true
            } catch {
                return false
            }
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return true
        } catch {
            return false
        }
    }
}
