import Foundation

enum DisplayPreferencesMigration {
    static let versionKey = "MemWatch.PreferencesMigrationVersion"
    static let currentVersion = 1
    static let legacySuiteName = "fyi.kadir.AmbientSync"

    // Keep the serialized keys stable. The migration moves values from the
    // old bundle domain into the unified app's defaults domain only when the
    // unified app does not already have a value.
    static let legacyKeys = [
        AppPreferences.storageKey,
        "AmbientSync.KeepAwakeStateJSON",
        "AmbientSync.KeepAwakePluggedOnly",
        "AmbientSync.KeepDisplayAwakeOnWake",
        "AmbientSync.AutoBrightnessEnabled",
        "AmbientSync.LastVolume",
        "AmbientSync.StatusBarDetailMode",
        "com.ambientsync.hidpi.savedmode",
        "com.ambientsync.hidpi.enabled",
        "com.ambientsync.hidpi.stateText",
        "AmbientSync.DisplayConnection.SoftwareDisconnected"
    ]

    @discardableResult
    static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacySuiteName)
    ) -> Bool {
        let version = defaults.integer(forKey: versionKey)
        guard version < currentVersion else { return false }

        if let legacyDefaults {
            for key in legacyKeys {
                guard defaults.object(forKey: key) == nil,
                      let value = legacyDefaults.object(forKey: key) else {
                    continue
                }
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(currentVersion, forKey: versionKey)
        return true
    }
}
