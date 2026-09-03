import Foundation

/// Owns the low-level brightness hardware dependencies. DisplayCoordinator
/// remains responsible for policy and presentation state, while this object
/// is the single owner of the sensor/DDC/internal-display controller instances.
@MainActor
final class DisplayBrightnessCoordinator {
    let reader: AmbientLightReader?
    let writer: M1DDCWriter
    let operationGate: DisplayPowerOperationGate
    let internalDisplayController: InternalDisplayBrightnessController?

    init(
        reader: AmbientLightReader? = AmbientLightReader(),
        writer: M1DDCWriter? = nil,
        operationGate: DisplayPowerOperationGate = .shared,
        internalDisplayController: InternalDisplayBrightnessController? = InternalDisplayBrightnessController()
    ) {
        self.reader = reader
        self.operationGate = operationGate
        self.writer = writer ?? M1DDCWriter(operationGate: operationGate)
        self.internalDisplayController = internalDisplayController
    }

    func isDDCAvailable(refresh: Bool = false) async -> Bool {
        await writer.isAvailable(refresh: refresh)
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

    init(operationGate: DisplayPowerOperationGate = .shared) {
        let modeSwitcher = CGSModeSwitcher(operationGate: operationGate)
        self.modeSwitcher = modeSwitcher
        self.featureController = HiDPIFeatureController()
        self.refreshService = HiDPIRefreshService(
            modeSwitcher: modeSwitcher,
            featureController: featureController
        )
    }
}
