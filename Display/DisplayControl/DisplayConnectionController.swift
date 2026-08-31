import Combine
import CoreGraphics
import Foundation

@MainActor
final class DisplayConnectionController: ObservableObject {
    static let shared = DisplayConnectionController()

    @Published private(set) var snapshot: DisplayConnectionSnapshot = .initial
    @Published private(set) var isBusy = false

    var isAvailable: Bool {
        backend.isAvailable
    }

    private static let softwareDisconnectDefaultsKey = "AmbientSync.DisplayConnection.SoftwareDisconnected"
    private static let reconnectAttemptCount = 3
    private static let reconnectRetryDelayNanoseconds: UInt64 = 400_000_000

    private let backend: DisplayConnectionBackend
    private let identity: DisplayConnectionIdentity
    private let defaults: UserDefaults

    init(
        backend: DisplayConnectionBackend = PrivateDisplayConnectionBackend(),
        identity: DisplayConnectionIdentity = .samsungS60UD,
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.identity = identity
        self.defaults = defaults
    }

    @discardableResult
    func refresh() -> DisplayConnectionSnapshot {
        guard backend.isAvailable else {
            return publish(
                phase: .unsupported,
                displayID: nil,
                isOnline: false,
                isActive: false,
                canToggle: false,
                message: "Yazılımsal ekran ayırma bu macOS sürümünde kullanılamıyor."
            )
        }

        do {
            let allIDs = try backend.allDisplayIDs()
            guard let displayID = resolveTargetDisplayID(from: allIDs) else {
                return publish(
                    phase: .physicallyDisconnected,
                    displayID: nil,
                    isOnline: false,
                    isActive: false,
                    canToggle: false,
                    message: "Samsung S60UD fiziksel olarak bağlı görünmüyor."
                )
            }

            let isOnline = CGDisplayIsOnline(displayID) != 0
            let isActive = CGDisplayIsActive(displayID) != 0
            let phase = DisplayConnectionPolicy.phase(
                targetFoundInPrivateList: true,
                isOnline: isOnline,
                isActive: isActive,
                softwareDisconnectRequested: softwareDisconnectRequested
            )

            let message: String
            switch phase {
            case .connected where softwareDisconnectRequested:
                message = "Samsung S60UD sistem tarafından yeniden etkinleşti; ayrılma isteği korunuyor."
            case .connected:
                message = "Samsung S60UD bağlı."
            case .softwareDisconnected:
                message = "Samsung S60UD yazılımsal olarak ayrıldı."
            case .physicallyDisconnected:
                message = "Samsung S60UD bağlı fakat aktif görünmüyor; yazılımsal ayırma işareti yok."
            default:
                message = "Samsung S60UD bağlantı durumu güncellendi."
            }

            return publish(
                phase: phase,
                displayID: displayID,
                isOnline: isOnline,
                isActive: isActive,
                canToggle: phase == .connected || phase == .softwareDisconnected,
                message: message
            )
        } catch {
            return publishFailure(error)
        }
    }

    /// Reconciles the actual WindowServer state with the user's persisted intent.
    /// If sleep/wake or another system event restores a display that AmbientSync had
    /// intentionally disconnected, we safely disconnect it again as long as another
    /// active display remains available.
    @discardableResult
    func reconcileDesiredState() -> DisplayConnectionSnapshot {
        let current = refresh()
        guard softwareDisconnectRequested, current.phase == .connected else {
            return current
        }
        return disconnect(preserveRequestOnFailure: true)
    }

    @discardableResult
    func toggle() async -> DisplayConnectionSnapshot {
        let current = refresh()
        switch current.phase {
        case .connected:
            return disconnect()
        case .softwareDisconnected:
            return await reconnect()
        default:
            return current
        }
    }

    @discardableResult
    func disconnect(preserveRequestOnFailure: Bool = false) -> DisplayConnectionSnapshot {
        guard !isBusy else { return snapshot }
        isBusy = true
        defer { isBusy = false }

        let current = refresh()
        guard current.phase == .connected, let displayID = current.displayID else {
            return current
        }

        let activeIDs = activeDisplayIDs()
        guard DisplayConnectionPolicy.canDisable(
            targetDisplayID: displayID,
            activeDisplayIDs: activeIDs
        ) else {
            return publish(
                phase: .failed,
                displayID: displayID,
                isOnline: current.isOnline,
                isActive: current.isActive,
                canToggle: true,
                message: "Son aktif ekran kapatılamaz. Başka bir ekran aktif olmalı."
            )
        }

        _ = publish(
            phase: .disconnecting,
            displayID: displayID,
            isOnline: true,
            isActive: true,
            canToggle: false,
            message: "Samsung S60UD ayrılıyor…"
        )

        do {
            try backend.setDisplayEnabled(false, displayID: displayID)
            setSoftwareDisconnectRequested(true)
            return refresh()
        } catch {
            if !preserveRequestOnFailure {
                setSoftwareDisconnectRequested(false)
            }
            return publishFailure(error, displayID: displayID)
        }
    }

    @discardableResult
    func reconnect() async -> DisplayConnectionSnapshot {
        guard !isBusy else { return snapshot }
        isBusy = true
        defer { isBusy = false }

        guard backend.isAvailable else { return refresh() }

        var lastError: Error?

        for attempt in 1...Self.reconnectAttemptCount {
            do {
                // Always re-enumerate here. A software-disabled display drops out of
                // public lists and its CGDirectDisplayID must not be treated as durable.
                let allIDs = try backend.allDisplayIDs()
                guard let displayID = resolveTargetDisplayID(from: allIDs) else {
                    return publish(
                        phase: .physicallyDisconnected,
                        displayID: nil,
                        isOnline: false,
                        isActive: false,
                        canToggle: false,
                        message: "Samsung S60UD private ekran listesinde bulunamadı."
                    )
                }

                if CGDisplayIsOnline(displayID) != 0 && CGDisplayIsActive(displayID) != 0 {
                    setSoftwareDisconnectRequested(false)
                    return refresh()
                }

                _ = publish(
                    phase: .reconnecting,
                    displayID: displayID,
                    isOnline: CGDisplayIsOnline(displayID) != 0,
                    isActive: CGDisplayIsActive(displayID) != 0,
                    canToggle: false,
                    message: "Samsung S60UD yeniden bağlanıyor… (\(attempt)/\(Self.reconnectAttemptCount))"
                )

                try backend.setDisplayEnabled(true, displayID: displayID)
                try? await Task.sleep(nanoseconds: Self.reconnectRetryDelayNanoseconds)

                // Re-enumerate again before verification; the transaction itself may
                // cause WindowServer to assign/re-surface a different display id.
                let verificationIDs = try backend.allDisplayIDs()
                if let verifiedDisplayID = resolveTargetDisplayID(from: verificationIDs),
                   CGDisplayIsOnline(verifiedDisplayID) != 0,
                   CGDisplayIsActive(verifiedDisplayID) != 0 {
                    setSoftwareDisconnectRequested(false)
                    return refresh()
                }
            } catch {
                lastError = error
            }

            if attempt < Self.reconnectAttemptCount {
                try? await Task.sleep(nanoseconds: Self.reconnectRetryDelayNanoseconds)
            }
        }

        let detail = lastError.map { " Son hata: \($0.localizedDescription)" } ?? ""
        return publish(
            phase: .failed,
            displayID: nil,
            isOnline: false,
            isActive: false,
            canToggle: true,
            message: "Samsung S60UD yeniden bağlanamadı. Kabloyu çıkarıp takmak veya yeniden başlatmak gerekebilir.\(detail)"
        )
    }

    private var softwareDisconnectRequested: Bool {
        defaults.bool(forKey: Self.softwareDisconnectDefaultsKey)
    }

    private func setSoftwareDisconnectRequested(_ value: Bool) {
        defaults.set(value, forKey: Self.softwareDisconnectDefaultsKey)
    }

    private func resolveTargetDisplayID(from ids: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        let hardwareMatches = ids.filter { displayID in
            guard CGDisplayIsBuiltin(displayID) == 0 else { return false }
            return CGDisplayVendorNumber(displayID) == identity.vendorID &&
                CGDisplayModelNumber(displayID) == identity.productID
        }

        if let exact = hardwareMatches.first(where: {
            CGDisplaySerialNumber($0) == identity.serialNumber
        }) {
            return exact
        }

        // Some disabled-display paths temporarily expose an unreadable serial.
        // Vendor/product fallback is accepted only when it is unambiguous.
        if hardwareMatches.count == 1 {
            return hardwareMatches[0]
        }

        return nil
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var ids = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        let result = ids.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(count, buffer.baseAddress, &count)
        }
        guard result == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    @discardableResult
    private func publish(
        phase: DisplayConnectionPhase,
        displayID: CGDirectDisplayID?,
        isOnline: Bool,
        isActive: Bool,
        canToggle: Bool,
        message: String
    ) -> DisplayConnectionSnapshot {
        let next = DisplayConnectionSnapshot(
            phase: phase,
            displayID: displayID,
            name: identity.name,
            isOnline: isOnline,
            isActive: isActive,
            canToggle: canToggle,
            message: message
        )
        snapshot = next
        return next
    }

    private func publishFailure(
        _ error: Error,
        displayID: CGDirectDisplayID? = nil
    ) -> DisplayConnectionSnapshot {
        publish(
            phase: .failed,
            displayID: displayID,
            isOnline: false,
            isActive: false,
            canToggle: true,
            message: error.localizedDescription
        )
    }
}
