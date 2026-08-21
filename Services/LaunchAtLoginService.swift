import Foundation
import ServiceManagement

struct LaunchAtLoginService {
    func currentState() -> LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .needsSetup
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            if service.status != .enabled {
                try service.register()
            }
            return
        }

        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
    }
}
