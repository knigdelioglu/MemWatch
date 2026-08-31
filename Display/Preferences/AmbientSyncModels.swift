import Foundation
import SwiftUI

struct AmbientSyncProfile: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var lowBrightness: Int
    var midBrightness: Int
    var highBrightness: Int
    var smoothing: Double
    var updateThreshold: Int
    var minInterval: Double

    static let defaultProfiles: [AmbientSyncProfile] = [
        AmbientSyncProfile(id: "ultra_dark", name: "Ultra Dark", lowBrightness: 1, midBrightness: 15, highBrightness: 40, smoothing: 0.15, updateThreshold: 2, minInterval: 4.0),
        AmbientSyncProfile(id: "night", name: "Night", lowBrightness: 8, midBrightness: 22, highBrightness: 42, smoothing: 0.18, updateThreshold: 2, minInterval: 4.0),
        AmbientSyncProfile(id: "balanced", name: "Balanced", lowBrightness: 14, midBrightness: 44, highBrightness: 76, smoothing: 0.28, updateThreshold: 3, minInterval: 2.0),
        AmbientSyncProfile(id: "soft", name: "Soft", lowBrightness: 10, midBrightness: 34, highBrightness: 66, smoothing: 0.22, updateThreshold: 2, minInterval: 3.0),
        AmbientSyncProfile(id: "bright", name: "Bright", lowBrightness: 18, midBrightness: 58, highBrightness: 92, smoothing: 0.36, updateThreshold: 4, minInterval: 1.2),
    ]
}

struct DisplayCalibration: Codable, Hashable {
    var lowLux: Double
    var midLux: Double
    var highLux: Double

    static let `default` = DisplayCalibration(lowLux: 20, midLux: 350, highLux: 650)
    static let legacyDefault = DisplayCalibration(lowLux: 20, midLux: 180, highLux: 650)
}

struct DisplaySettings: Codable, Hashable {
    var selectedProfileID: String
    var calibration: DisplayCalibration
    var lastBrightness: Int?
}

struct AppPreferences: Codable, Hashable {
    var selectedDisplayKey: String?
    var profiles: [AmbientSyncProfile]
    var displaySettingsByKey: [String: DisplaySettings]

    static let storageKey = "AmbientSync.AppPreferences"

    static func `default`() -> AppPreferences {
        AppPreferences(
            selectedDisplayKey: nil,
            profiles: AmbientSyncProfile.defaultProfiles,
            displaySettingsByKey: [:]
        )
    }
}

struct CalibrationSession: Hashable {
    enum Step: String {
        case low
        case mid
        case high
    }

    var displayKey: String
    var profileID: String
    var step: Step
    var lowLux: Double?
    var midLux: Double?
    var highLux: Double?

    var instruction: String {
        switch step {
        case .low:
            return "Low light. Put the monitor where you want the dark-room behavior."
        case .mid:
            return "Medium light. Move to your usual work lighting."
        case .high:
            return "Bright light. Capture the brightest normal room light."
        }
    }

    var stepIndex: Int {
        switch step {
        case .low: return 0
        case .mid: return 1
        case .high: return 2
        }
    }

    var stepCount: Int {
        3
    }

    var captureButtonTitle: String {
        switch step {
        case .low:
            return "Capture low"
        case .mid:
            return "Capture mid"
        case .high:
            return "Capture high"
        }
    }
}

struct ExternalDisplayInfo: Hashable {
    var displayIndex: String
    var displayID: UInt32?
    var productName: String
    var serial: String?
    var systemUUID: String?
    var ioLocation: String?

    var displayKey: String {
        let identity = serial.flatMap { $0.isEmpty ? nil : $0 }
            ?? systemUUID.flatMap { $0.isEmpty ? nil : $0 }
            ?? displayIndex
        return "\(productName)|\(identity)"
    }

    var displayLabel: String {
        productName.isEmpty ? "External display" : productName
    }
}

@MainActor
final class AmbientSyncStore: ObservableObject {
    @Published var preferences: AppPreferences {
        didSet { save() }
    }

    init(preferences: AppPreferences = .default()) {
        DisplayPreferencesMigration.migrateIfNeeded()
        let loadedPreferences = Self.loadPreferences() ?? preferences
        let migratedPreferences = Self.migratePreferencesIfNeeded(loadedPreferences)
        self.preferences = migratedPreferences
        if migratedPreferences != loadedPreferences {
            save()
        }
        if self.preferences.profiles.isEmpty {
            self.preferences.profiles = AmbientSyncProfile.defaultProfiles
        }
    }

    var profiles: [AmbientSyncProfile] {
        preferences.profiles
    }

    func profile(id: String) -> AmbientSyncProfile {
        if let profile = preferences.profiles.first(where: { $0.id == id }) {
            return profile
        }
        return preferences.profiles.first ?? AmbientSyncProfile.defaultProfiles[0]
    }

    func activeProfile(for displayKey: String) -> AmbientSyncProfile {
        profile(id: settings(for: displayKey).selectedProfileID)
    }

    func settings(for displayKey: String) -> DisplaySettings {
        if let existing = preferences.displaySettingsByKey[displayKey] {
            return existing
        }
        return DisplaySettings(
            selectedProfileID: AmbientSyncProfile.defaultProfiles[0].id,
            calibration: .default,
            lastBrightness: nil
        )
    }

    func ensureSettings(for displayKey: String) -> DisplaySettings {
        if let existing = preferences.displaySettingsByKey[displayKey] {
            return existing
        }
        let created = DisplaySettings(
            selectedProfileID: AmbientSyncProfile.defaultProfiles[0].id,
            calibration: .default,
            lastBrightness: nil
        )
        var updated = preferences
        updated.displaySettingsByKey[displayKey] = created
        preferences = updated
        return created
    }

    func selectedDisplayKeyOrCreate(_ fallback: String) -> String {
        if let key = preferences.selectedDisplayKey {
            return key
        }
        preferences.selectedDisplayKey = fallback
        return fallback
    }

    func setSelectedDisplayKey(_ key: String) {
        var updated = preferences
        updated.selectedDisplayKey = key
        preferences = updated
    }

    func setLastBrightness(_ value: Int?, for displayKey: String) {
        var settings = ensureSettings(for: displayKey)
        settings.lastBrightness = value
        var updated = preferences
        updated.displaySettingsByKey[displayKey] = settings
        preferences = updated
    }

    func lastBrightness(for displayKey: String) -> Int? {
        settings(for: displayKey).lastBrightness
    }

    func setSelectedProfileID(_ id: String, for displayKey: String) {
        var settings = ensureSettings(for: displayKey)
        settings.selectedProfileID = id
        var updated = preferences
        updated.displaySettingsByKey[displayKey] = settings
        preferences = updated
    }

    func setCalibration(_ calibration: DisplayCalibration, for displayKey: String) {
        var settings = ensureSettings(for: displayKey)
        settings.calibration = calibration
        var updated = preferences
        updated.displaySettingsByKey[displayKey] = settings
        preferences = updated
    }

    func updateProfile(_ profile: AmbientSyncProfile) {
        guard let index = preferences.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = preferences
        updated.profiles[index] = profile
        preferences = updated
    }

    func duplicateProfile(from profile: AmbientSyncProfile, named name: String) {
        var copy = profile
        copy.id = UUID().uuidString
        copy.name = name
        var updated = preferences
        updated.profiles.append(copy)
        preferences = updated
    }

    func deleteProfile(id: String) {
        guard preferences.profiles.count > 1 else { return }
        var updated = preferences
        updated.profiles.removeAll { $0.id == id }
        for (key, settings) in updated.displaySettingsByKey where settings.selectedProfileID == id {
            var nextSettings = settings
            nextSettings.selectedProfileID = AmbientSyncProfile.defaultProfiles[0].id
            updated.displaySettingsByKey[key] = nextSettings
        }
        preferences = updated
    }

    func resetProfile(id: String) {
        guard let index = AmbientSyncProfile.defaultProfiles.firstIndex(where: { $0.id == id }) else { return }
        let defaults = AmbientSyncProfile.defaultProfiles[index]
        guard let currentIndex = preferences.profiles.firstIndex(where: { $0.id == id }) else {
            var updated = preferences
            updated.profiles.append(defaults)
            preferences = updated
            return
        }
        var updated = preferences
        updated.profiles[currentIndex] = defaults
        preferences = updated
    }

    func profileBinding(id: String) -> Binding<AmbientSyncProfile> {
        Binding(
            get: { [weak self] in
                self?.profile(id: id) ?? AmbientSyncProfile.defaultProfiles[0]
            },
            set: { [weak self] newValue in
                self?.updateProfile(newValue)
            }
        )
    }

    func selectedProfileID(for displayKey: String) -> String {
        settings(for: displayKey).selectedProfileID
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: AppPreferences.storageKey)
    }

    private static func loadPreferences() -> AppPreferences? {
        guard let data = UserDefaults.standard.data(forKey: AppPreferences.storageKey) else { return nil }
        return try? JSONDecoder().decode(AppPreferences.self, from: data)
    }

    private static func migratePreferencesIfNeeded(_ preferences: AppPreferences) -> AppPreferences {
        var updated = preferences
        var didChange = false

        for (displayKey, settings) in updated.displaySettingsByKey where settings.calibration == DisplayCalibration.legacyDefault {
            var nextSettings = settings
            nextSettings.calibration = .default
            updated.displaySettingsByKey[displayKey] = nextSettings
            didChange = true
        }

        return didChange ? updated : preferences
    }
}

