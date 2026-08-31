import Foundation

public struct OverrideValidationResult {
    public let isValid: Bool
    public let has5KNormal: Bool
    public let has5KHiDPI: Bool
    public let message: String
}

public struct HiDPIStatusOverview {
    public let systemOverrideExists: Bool
    public let bundledReferenceExists: Bool
    public let applicationSupportBackupExists: Bool
    public let systemMatchesBundledReference: Bool
    public let systemMissingButReferenceAvailable: Bool
    public let systemOverrideExistsButDoesNotMatchReference: Bool
    public let perfectQHDRecordsPresent: Bool
    public let installRequiresPrivilegedHelper: Bool
}

public final class HiDPIDisplayOverrideManager {
    public static func statusOverview() -> HiDPIStatusOverview {
        let systemExists = HiDPIOverrideReferenceStore.systemOverrideExists
        let bundledReferenceExists = HiDPIOverrideReferenceStore.bundledReferenceExists
        let applicationSupportBackupExists = HiDPIOverrideReferenceStore.applicationSupportBackupExists
        let systemMatchesReference = HiDPIOverrideReferenceStore.systemMatchesBundledReference()

        var perfectQHDRecordsPresent = false
        if systemExists, let record = try? HiDPIOverrideReferenceStore.systemOverrideRecord() {
            perfectQHDRecordsPresent = record.perfectQHDRecordsPresent
        }

        return HiDPIStatusOverview(
            systemOverrideExists: systemExists,
            bundledReferenceExists: bundledReferenceExists,
            applicationSupportBackupExists: applicationSupportBackupExists,
            systemMatchesBundledReference: systemMatchesReference,
            systemMissingButReferenceAvailable: !systemExists && (bundledReferenceExists || applicationSupportBackupExists),
            systemOverrideExistsButDoesNotMatchReference: systemExists && !systemMatchesReference,
            perfectQHDRecordsPresent: perfectQHDRecordsPresent,
            installRequiresPrivilegedHelper: bundledReferenceExists
        )
    }

    public static func validateExistingOverride() -> OverrideValidationResult {
        guard HiDPIOverrideReferenceStore.systemOverrideExists else {
            return OverrideValidationResult(
                isValid: false,
                has5KNormal: false,
                has5KHiDPI: false,
                message: "Sistemde override plist dosyası bulunamadı."
            )
        }

        guard let record = try? HiDPIOverrideReferenceStore.systemOverrideRecord() else {
            return OverrideValidationResult(
                isValid: false,
                has5KNormal: false,
                has5KHiDPI: false,
                message: "Plist dosyası okunamadı veya scale-resolutions alanı eksik."
            )
        }

        let has5KNormal = record.hasPerfectQHDNormalRecord
        let has5KHiDPI = record.hasPerfectQHDHiDPIRecord
        let isValid = has5KNormal && has5KHiDPI
        let message = isValid ? "Perfect QHD HiDPI çözünürlük girdileri doğrulandı." : "Eksik 5K çözünürlük girdileri var."

        return OverrideValidationResult(
            isValid: isValid,
            has5KNormal: has5KNormal,
            has5KHiDPI: has5KHiDPI,
            message: message
        )
    }
}
