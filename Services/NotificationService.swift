import Foundation
import UserNotifications

enum NotificationAuthorizationState: String {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var displayName: String {
        switch self {
        case .notDetermined: return "Permission needed"
        case .denied: return "Blocked in System Settings"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporary"
        case .unknown: return "Unknown"
        }
    }

    var canDeliver: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }
}

final class NotificationService {
    var onAuthorizationChange: ((NotificationAuthorizationState) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            self?.publishAuthorization(settings.authorizationStatus)
        }
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshAuthorizationStatus()
        }
    }

    func deliver(_ payload: MemoryAlertPayload) {
        center.getNotificationSettings { [weak self] settings in
            guard self?.map(settings.authorizationStatus).canDeliver == true else { return }

            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "memwatch-\(payload.kind.rawValue)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            self?.center.add(request)
        }
    }

    private func publishAuthorization(_ status: UNAuthorizationStatus) {
        let mapped = map(status)
        DispatchQueue.main.async { [weak self] in
            self?.onAuthorizationChange?(mapped)
        }
    }

    private func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }
}
