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
    /// Operational DDC selection. This may change when macOS rebuilds the
    /// display enumeration after a mode transition and must not be used as
    /// the durable settings identity.
    var selectedDisplayKey: String?
    /// Stable physical identity of the selected display, when discovery can
    /// prove one. This is also used to migrate a legacy raw-key record safely.
    var selectedDisplayFingerprint: String?
    /// Last complete discovered identity. The runtime display key may change
    /// across HDR/SDR, so this is a restart-safe bridge between two verified
    /// representations of the same panel (for example serial -> UUID).
    /// It is stored only when a durable serial or verified display UUID exists.
    var selectedDisplayIdentity: ExternalDisplayInfo?
    var profiles: [AmbientSyncProfile]
    var displaySettingsByKey: [String: DisplaySettings]

    static let storageKey = "AmbientSync.AppPreferences"

    static func `default`() -> AppPreferences {
        AppPreferences(
            selectedDisplayKey: nil,
            selectedDisplayFingerprint: nil,
            selectedDisplayIdentity: nil,
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
    /// The complete identity captured when calibration started. Keeping this
    /// separate from the operational display key prevents a mode transition
    /// from saving calibration into a different physical panel's settings.
    var displayIdentity: ExternalDisplayInfo?
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

struct ExternalDisplayInfo: Codable, Hashable, Sendable {
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

    /// A display key is an operational DDC identifier and may change when the
    /// DDC enumeration is rebuilt. Keep physical continuity separate from it.
    /// `systemUUID` is accepted as a physical identity only after the DDC
    /// discovery path verifies it against CoreGraphics' display-scoped UUID;
    /// a Mac/host UUID must never be passed here.
    var physicalDisplayFingerprint: String? {
        durablePhysicalDisplayFingerprint
    }

    /// Only a serial or verified display UUID is safe for physical continuity
    /// and persisted settings. A port/location identifies the connection path,
    /// not the panel, so it must not make a hot-swapped monitor inherit state.
    var durablePhysicalDisplayFingerprint: String? {
        if let serial = normalizedSerial {
            // A real panel serial is the strongest durable identity and wins
            // over a mode-specific UUID representation.
            return "serial:\(serial)"
        }
        if let systemUUID = normalizedSystemUUID {
            return "uuid:\(systemUUID)"
        }
        return nil
    }

    var hasStablePhysicalIdentity: Bool {
        physicalDisplayFingerprint != nil
    }

    /// A legacy runtime key is safe to migrate directly only when its own
    /// identity component is a serial or verified display UUID. An index-only
    /// key can be reused for a different panel.
    var hasStableDisplayKeyIdentity: Bool {
        normalizedSerial != nil || normalizedSystemUUID != nil
    }

    /// Matches the identity component of a legacy `productName|identity` key
    /// without trusting the product name, which may also change during a
    /// display-parameter transition.
    func legacyDisplayKeyMatchesStableIdentity(_ key: String) -> Bool {
        guard let keyIdentity = key.split(separator: "|").last.map(String.init),
              let normalizedKeyIdentity = normalizedIdentityValue(keyIdentity) else {
            return false
        }
        return normalizedSerial == normalizedKeyIdentity || normalizedSystemUUID == normalizedKeyIdentity
    }

    /// Returns true only when the available stable identity agrees. A
    /// display index/CGDirectDisplayID is deliberately not used: those values
    /// can be reassigned during HDR/SDR and display-mode transitions.
    func isSamePhysicalDisplay(as other: ExternalDisplayInfo) -> Bool {
        if let lhsSerial = normalizedSerial,
           let rhsSerial = other.normalizedSerial {
            return lhsSerial == rhsSerial
        }

        if let lhsUUID = normalizedSystemUUID,
           let rhsUUID = other.normalizedSystemUUID {
            return lhsUUID == rhsUUID
        }

        // Without a serial or verified display UUID there is no proof of
        // panel continuity. In particular, never use a reused IO location or
        // display index to transfer accepted brightness/settings.
        return false
    }

    private var normalizedSystemUUID: String? {
        normalizedIdentityValue(systemUUID)
    }

    private var normalizedSerial: String? {
        normalizedIdentityValue(serial)
    }

    private func normalizedIdentityValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized.lowercased()
    }

    var displayLabel: String {
        productName.isEmpty ? "External display" : productName
    }
}

@MainActor
final class AmbientSyncStore: ObservableObject {
    private static let physicalSettingsKeyPrefix = "physical:"

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

    func activeProfile(for display: ExternalDisplayInfo) -> AmbientSyncProfile {
        profile(id: settings(for: display).selectedProfileID)
    }

    func settings(for displayKey: String) -> DisplaySettings {
        let resolvedKey = resolvedSettingsKey(for: displayKey)
        if let existing = preferences.displaySettingsByKey[resolvedKey] {
            return existing
        }
        return Self.defaultDisplaySettings()
    }

    /// Returns settings under the stable physical key when one is available.
    /// The first access also performs a safe, one-way migration from a legacy
    /// runtime display key so old brightness/profile/calibration data is not
    /// stranded when macOS exposes the same panel under a new display key.
    func settings(for display: ExternalDisplayInfo) -> DisplaySettings {
        let key = canonicalizeSettings(for: display)
        return preferences.displaySettingsByKey[key] ?? Self.defaultDisplaySettings()
    }

    func ensureSettings(for displayKey: String) -> DisplaySettings {
        let resolvedKey = resolvedSettingsKey(for: displayKey)
        if let existing = preferences.displaySettingsByKey[resolvedKey] {
            return existing
        }
        let created = Self.defaultDisplaySettings()
        var updated = preferences
        updated.displaySettingsByKey[resolvedKey] = created
        preferences = updated
        return created
    }

    func ensureSettings(for display: ExternalDisplayInfo) -> DisplaySettings {
        var updated = preferences
        let key = prepareSettings(for: display, in: &updated)
        if let existing = updated.displaySettingsByKey[key] {
            if updated != preferences {
                preferences = updated
            }
            return existing
        }

        let created = Self.defaultDisplaySettings()
        updated.displaySettingsByKey[key] = created
        preferences = updated
        return created
    }

    /// Canonical key used only for durable per-display settings. DDC calls
    /// continue to use `ExternalDisplayInfo.displayKey` as their operational
    /// selector.
    func storageKey(for display: ExternalDisplayInfo) -> String {
        guard let fingerprint = display.durablePhysicalDisplayFingerprint else {
            // Without a stable identity, retain the existing runtime-key
            // isolation rather than guessing that two panels are the same.
            return display.displayKey
        }
        return Self.physicalSettingsKey(for: fingerprint)
    }

    /// Records the runtime selector and the stable physical identity
    /// independently. `previousDisplay` allows a running process to bridge a
    /// fingerprint representation change (for example serial -> UUID) after
    /// a display-parameter transition.
    func setSelectedDisplay(
        _ display: ExternalDisplayInfo,
        previousDisplay: ExternalDisplayInfo? = nil
    ) {
        var updated = preferences
        // On a cold start there is no in-memory previousDisplayInfo. Reuse
        // only the last verified durable identity as the continuity witness;
        // an IO location alone is intentionally never persisted as one.
        let continuityDisplay = previousDisplay ?? updated.selectedDisplayIdentity

        if let continuityDisplay,
           continuityDisplay.isSamePhysicalDisplay(as: display) {
            let previousKey = storageKey(for: continuityDisplay)
            _ = prepareSettings(for: continuityDisplay, in: &updated)
            let nextKey = prepareSettings(for: display, in: &updated)

            if previousKey != nextKey {
                if let previousSettings = updated.displaySettingsByKey[previousKey] {
                    // A mode transition can leave behind a duplicate B
                    // record, including a stale non-default brightness. The
                    // settings attached to the currently active, verified
                    // continuityDisplay are the winning state for this panel.
                    updated.displaySettingsByKey[nextKey] = previousSettings
                }
                updated.displaySettingsByKey.removeValue(forKey: previousKey)
            }
        } else {
            _ = prepareSettings(for: display, in: &updated)
        }

        updated.selectedDisplayKey = display.displayKey
        updated.selectedDisplayFingerprint = display.durablePhysicalDisplayFingerprint
        updated.selectedDisplayIdentity = display.durablePhysicalDisplayFingerprint == nil ? nil : display
        if updated != preferences {
            preferences = updated
        }
    }

    func selectedDisplayKeyOrCreate(_ fallback: String) -> String {
        if let key = preferences.selectedDisplayKey {
            return key
        }
        var updated = preferences
        updated.selectedDisplayKey = fallback
        updated.selectedDisplayFingerprint = nil
        updated.selectedDisplayIdentity = nil
        preferences = updated
        return fallback
    }

    func setSelectedDisplayKey(_ key: String) {
        var updated = preferences
        updated.selectedDisplayKey = key
        // A raw runtime key carries no proof that it belongs to the previous
        // physical display. Clear the durable alias until discovery supplies
        // a verified ExternalDisplayInfo again.
        updated.selectedDisplayFingerprint = nil
        updated.selectedDisplayIdentity = nil
        preferences = updated
    }

    func setLastBrightness(_ value: Int?, for displayKey: String) {
        let resolvedKey = resolvedSettingsKey(for: displayKey)
        updateSettings(forStorageKey: resolvedKey) { settings in
            settings.lastBrightness = value
        }
    }

    func setLastBrightness(_ value: Int?, for display: ExternalDisplayInfo) {
        updateSettings(for: display) { settings in
            settings.lastBrightness = value
        }
    }

    func lastBrightness(for displayKey: String) -> Int? {
        settings(for: displayKey).lastBrightness
    }

    func lastBrightness(for display: ExternalDisplayInfo) -> Int? {
        settings(for: display).lastBrightness
    }

    func setSelectedProfileID(_ id: String, for displayKey: String) {
        let resolvedKey = resolvedSettingsKey(for: displayKey)
        updateSettings(forStorageKey: resolvedKey) { settings in
            settings.selectedProfileID = id
        }
    }

    func setSelectedProfileID(_ id: String, for display: ExternalDisplayInfo) {
        updateSettings(for: display) { settings in
            settings.selectedProfileID = id
        }
    }

    func setCalibration(_ calibration: DisplayCalibration, for displayKey: String) {
        let resolvedKey = resolvedSettingsKey(for: displayKey)
        updateSettings(forStorageKey: resolvedKey) { settings in
            settings.calibration = calibration
        }
    }

    func setCalibration(_ calibration: DisplayCalibration, for display: ExternalDisplayInfo) {
        updateSettings(for: display) { settings in
            settings.calibration = calibration
        }
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

    func selectedProfileID(for display: ExternalDisplayInfo) -> String {
        settings(for: display).selectedProfileID
    }

    private static func defaultDisplaySettings() -> DisplaySettings {
        DisplaySettings(
            selectedProfileID: AmbientSyncProfile.defaultProfiles[0].id,
            calibration: .default,
            lastBrightness: nil
        )
    }

    private static func physicalSettingsKey(for fingerprint: String) -> String {
        "\(physicalSettingsKeyPrefix)\(fingerprint)"
    }

    private func resolvedSettingsKey(for displayKey: String) -> String {
        // A selected runtime key may have already been migrated to its
        // canonical physical key. Resolve that alias without allowing an
        // unrelated runtime key to inherit another panel's settings.
        if preferences.selectedDisplayKey == displayKey,
           let fingerprint = preferences.selectedDisplayFingerprint {
            let canonicalKey = Self.physicalSettingsKey(for: fingerprint)
            if preferences.displaySettingsByKey[canonicalKey] != nil {
                return canonicalKey
            }
        }
        return displayKey
    }

    private func canonicalizeSettings(for display: ExternalDisplayInfo) -> String {
        var updated = preferences
        let key = prepareSettings(for: display, in: &updated)
        if updated != preferences {
            preferences = updated
        }
        return key
    }

    /// Prepares the settings key and migrates legacy values into it. The
    /// selected-display fallback is accepted only when the persisted
    /// fingerprint or legacy stable identity matches the newly discovered
    /// physical identity.
    @discardableResult
    private func prepareSettings(
        for display: ExternalDisplayInfo,
        in updated: inout AppPreferences
    ) -> String {
        let canonicalKey = storageKey(for: display)
        guard canonicalKey != display.displayKey else {
            return canonicalKey
        }

        if updated.displaySettingsByKey[canonicalKey] == nil {
            // A raw key containing the display's serial/UUID is safe to
            // migrate directly. An index-only key is intentionally not: a
            // different panel can be assigned the same index later.
            if display.hasStableDisplayKeyIdentity,
               let legacySettings = updated.displaySettingsByKey[display.displayKey] {
                updated.displaySettingsByKey[canonicalKey] = legacySettings
            } else if let selectedKey = updated.selectedDisplayKey,
                      selectedKey != display.displayKey,
                      ((display.durablePhysicalDisplayFingerprint != nil &&
                        updated.selectedDisplayFingerprint == display.durablePhysicalDisplayFingerprint) ||
                       display.legacyDisplayKeyMatchesStableIdentity(selectedKey)),
                      let legacySettings = updated.displaySettingsByKey[selectedKey] {
                // This is the safe restart bridge for a legacy A -> B key
                // change: the old selected key and the new display both carry
                // the same persisted physical fingerprint.
                updated.displaySettingsByKey[canonicalKey] = legacySettings
            }
        }

        guard updated.displaySettingsByKey[canonicalKey] != nil else {
            return canonicalKey
        }

        if display.hasStableDisplayKeyIdentity {
            updated.displaySettingsByKey.removeValue(forKey: display.displayKey)
        }
        if let selectedKey = updated.selectedDisplayKey,
           selectedKey != canonicalKey,
           ((display.durablePhysicalDisplayFingerprint != nil &&
             updated.selectedDisplayFingerprint == display.durablePhysicalDisplayFingerprint) ||
            display.legacyDisplayKeyMatchesStableIdentity(selectedKey)) {
            updated.displaySettingsByKey.removeValue(forKey: selectedKey)
        }
        return canonicalKey
    }

    private func updateSettings(
        forStorageKey storageKey: String,
        _ mutate: (inout DisplaySettings) -> Void
    ) {
        var updated = preferences
        var settings = updated.displaySettingsByKey[storageKey] ?? Self.defaultDisplaySettings()
        mutate(&settings)
        updated.displaySettingsByKey[storageKey] = settings
        guard updated != preferences else { return }
        preferences = updated
    }

    private func updateSettings(
        for display: ExternalDisplayInfo,
        _ mutate: (inout DisplaySettings) -> Void
    ) {
        var updated = preferences
        let storageKey = prepareSettings(for: display, in: &updated)
        var settings = updated.displaySettingsByKey[storageKey] ?? Self.defaultDisplaySettings()
        mutate(&settings)
        updated.displaySettingsByKey[storageKey] = settings
        guard updated != preferences else { return }
        preferences = updated
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
