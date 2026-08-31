import Foundation

struct VolumeMenuTitleState: Equatable {
    let soundTitle: String
    let volumeStatusTitle: String
    let topVolumeStatusTitle: String
    let muteItemTitle: String
}

final class VolumeFeatureController {
    private let defaults: UserDefaults
    private let lastVolumeKey = "AmbientSync.LastVolume"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func loadLastVolume(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: "AmbientSync.LastVolume") as? Int ?? 0
    }

    func persistLastVolume(_ value: Int?) {
        defaults.set(value, forKey: lastVolumeKey)
    }

    func effectiveDisplayVolume(currentVolume: Int?, lastNonZeroVolume: Int) -> Int {
        currentVolume ?? lastNonZeroVolume
    }

    func menuTitles(currentVolume: Int?, lastNonZeroVolume: Int) -> VolumeMenuTitleState {
        let displayVolume = effectiveDisplayVolume(currentVolume: currentVolume, lastNonZeroVolume: lastNonZeroVolume)
        if displayVolume >= 0 {
            return VolumeMenuTitleState(
                soundTitle: "Ses: %\(displayVolume)",
                volumeStatusTitle: "Ses: %\(displayVolume)",
                topVolumeStatusTitle: "Ses: %\(displayVolume)",
                muteItemTitle: displayVolume == 0 ? "Sesi aç" : "Sessiz"
            )
        }

        return VolumeMenuTitleState(
            soundTitle: "Ses",
            volumeStatusTitle: "Ses: --",
            topVolumeStatusTitle: "Ses: --",
            muteItemTitle: "Sessiz"
        )
    }
}
