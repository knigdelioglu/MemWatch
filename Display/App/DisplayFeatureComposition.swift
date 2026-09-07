import Foundation

/// Owns the low-level brightness hardware dependencies. DisplayCoordinator
/// remains responsible for policy and presentation state, while this object
/// is the single owner of the sensor/DDC/internal-display controller instances.
@MainActor
final class DisplayBrightnessCoordinator {
    private(set) var reader: AmbientLightReader?
    let writer: M1DDCWriter
    let operationGate: DisplayPowerOperationGate
    let internalDisplayController: InternalDisplayBrightnessController?

    init(
        reader: AmbientLightReader? = AmbientLightReader(),
        writer: M1DDCWriter? = nil,
        operationGate: DisplayPowerOperationGate = .shared,
        targetOperationGate: TargetDisplayOperationGate = .shared,
        internalDisplayController: InternalDisplayBrightnessController? = InternalDisplayBrightnessController()
    ) {
        self.reader = reader
        self.operationGate = operationGate
        self.writer = writer ?? M1DDCWriter(
            operationGate: operationGate,
            targetOperationGate: targetOperationGate
        )
        self.internalDisplayController = internalDisplayController
    }

    func isDDCAvailable(refresh: Bool = false) async -> Bool {
        await writer.isAvailable(refresh: refresh)
    }

    @discardableResult
    func rebindAmbientLightSensor() -> Bool {
        guard ensureAmbientLightSensor() else { return false }
        return reader?.rebind() ?? false
    }

    /// Recreate the reader only from a bounded recovery path. Normal polling
    /// keeps the existing reader and its rebind behavior; this avoids resolving
    /// private ALS symbols on every tick while still recovering an initial nil
    /// reader or a reader whose client has stopped producing samples.
    @discardableResult
    func ensureAmbientLightSensor() -> Bool {
        guard reader == nil else { return true }
        reader = AmbientLightReader()
        return reader != nil
    }

    @discardableResult
    func recreateAmbientLightSensor() -> Bool {
        reader = AmbientLightReader()
        return reader != nil
    }

    /// Performs one controlled recovery probe. An existing reader is rebound
    /// first; it is recreated at most once for this probe if it still cannot
    /// produce lux. The caller owns any outer bounded retry schedule.
    func recoverAmbientLightSensor() -> (didRecreate: Bool, didRebind: Bool, lux: Double?) {
        var didRecreate = false
        if reader == nil {
            didRecreate = recreateAmbientLightSensor()
        }

        var didRebind = rebindAmbientLightSensor()
        var lux = reader?.readLux()
        if lux == nil && !didRecreate {
            didRecreate = recreateAmbientLightSensor()
            if didRecreate {
                didRebind = rebindAmbientLightSensor()
                lux = reader?.readLux()
            }
        }
        return (didRecreate, didRebind, lux)
    }

    var ambientLightSensorClientGeneration: UInt64 {
        reader?.clientGeneration ?? 0
    }

    var ambientLightSensorRebindCount: UInt64 {
        reader?.rebindCount ?? 0
    }

    func invalidateDDCBrightnessCache(for displayKey: String?) {
        let writer = writer
        Task { await writer.invalidateBrightnessCache(for: displayKey) }
    }
}

@MainActor
final class DisplayVolumeCoordinator {
    private let featureController: VolumeFeatureController
    private(set) var lastNonZeroVolume: Int

    init(featureController: VolumeFeatureController = VolumeFeatureController()) {
        self.featureController = featureController
        self.lastNonZeroVolume = VolumeFeatureController.loadLastVolume()
    }

    func record(_ volume: Int) {
        featureController.persistLastVolume(volume)
        if volume > 0 {
            lastNonZeroVolume = volume
        }
    }
}

/// Owns the private HiDPI controller graph so display lifecycle code does not
/// also own private mode-switching infrastructure directly.
@MainActor
final class DisplayHiDPICoordinator {
    let featureController: HiDPIFeatureController
    let refreshService: HiDPIRefreshService
    let modeSwitcher: CGSModeSwitcher

    init(
        operationGate: DisplayPowerOperationGate = .shared,
        targetOperationGate: TargetDisplayOperationGate = .shared
    ) {
        let modeSwitcher = CGSModeSwitcher(
            operationGate: operationGate,
            targetOperationGate: targetOperationGate
        )
        self.modeSwitcher = modeSwitcher
        self.featureController = HiDPIFeatureController()
        self.refreshService = HiDPIRefreshService(
            modeSwitcher: modeSwitcher,
            featureController: featureController
        )
    }
}
