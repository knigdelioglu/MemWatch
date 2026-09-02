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
        "com.ambientsync.hidpi.stateText"
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

/// Keeps the user's MemWatch software-disconnect intent separate from the
/// similarly named value owned by the retired AmbientSync app. The old
/// preferences migration once copied that value, so the corrective migration
/// removes only the deprecated MemWatch-domain copy and never touches the new
/// canonical intent key.
enum DisplayConnectionIntentMigration {
    static let versionKey = "MemWatch.DisplayConnectionIntentMigrationVersion"
    static let currentVersion = 1
    static let memWatchDefaultsKey = "MemWatch.DisplayConnection.SoftwareDisconnected"
    static let legacyDefaultsKey = "AmbientSync.DisplayConnection.SoftwareDisconnected"

    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.integer(forKey: versionKey) < currentVersion else { return false }

        // This is the value copied by DisplayPreferencesMigration v1. It is
        // not distinguishable from an old app intent, so it must no longer be
        // authoritative. A new MemWatch intent is stored under the canonical
        // key above and is intentionally preserved.
        defaults.removeObject(forKey: legacyDefaultsKey)
        defaults.set(currentVersion, forKey: versionKey)
        return true
    }
}
