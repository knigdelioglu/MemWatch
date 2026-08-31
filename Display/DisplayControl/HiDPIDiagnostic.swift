import CoreGraphics
import Foundation

public final class HiDPIDiagnostic {
    public static func run() {
        print("==================================================")
        print("         AmbientSync HiDPI Diagnostic             ")
        print("==================================================")

        print("\n[1] Reference store:")
        print("  - Bundled reference exists: \(HiDPIOverrideReferenceStore.bundledReferenceExists ? "YES" : "NO")")
        print("  - System override exists: \(HiDPIOverrideReferenceStore.systemOverrideExists ? "YES" : "NO")")
        print("  - Application Support backup exists: \(HiDPIOverrideReferenceStore.applicationSupportBackupExists ? "YES" : "NO")")
        print(String(format: "  - Target VendorID: 0x%04X | ProductID: 0x%04X | Serial: 0x%08X",
                     HiDPIOverrideReferenceStore.targetVendorID,
                     HiDPIOverrideReferenceStore.targetProductID,
                     HiDPIOverrideReferenceStore.targetSerialNumber))

        if let reference = try? HiDPIOverrideReferenceStore.bundledReferenceRecord() {
            print("  - Bundled SHA256: \(reference.sha256)")
            print("  - scale-resolutions count: \(reference.scaleResolutions.count)")
            print("  - 5120x2880 normal: \(reference.hasPerfectQHDNormalRecord ? "YES" : "NO")")
            print("  - 5120x2880 HiDPI/flexible: \(reference.hasPerfectQHDHiDPIRecord ? "YES" : "NO")")
        }

        print("\n[2] System override status:")
        let status = HiDPIDisplayOverrideManager.statusOverview()
        print("  - System override mevcut: \(status.systemOverrideExists ? "YES" : "NO")")
        print("  - Bundled reference mevcut: \(status.bundledReferenceExists ? "YES" : "NO")")
        print("  - Application Support backup mevcut: \(status.applicationSupportBackupExists ? "YES" : "NO")")
        print("  - System matches bundled reference: \(status.systemMatchesBundledReference ? "YES" : "NO")")
        print("  - Perfect QHD records present: \(status.perfectQHDRecordsPresent ? "YES" : "NO")")

        print("\n[3] Validation:")
        let validation = HiDPIDisplayOverrideManager.validateExistingOverride()
        print("  - \(validation.message)")
        print("  - 5K normal: \(validation.has5KNormal ? "YES" : "NO")")
        print("  - 5K HiDPI: \(validation.has5KHiDPI ? "YES" : "NO")")

        print("\n[4] Reference comparison:")
        let diff = HiDPIOverridePlistBuilder.compareSystemOverrideWithBundledReference()
        print("  - Equal: \(diff.areEqual ? "YES" : "NO")")
        print("  - \(diff.diffDetails)")

        print("\n==================================================")
        print("             Teşhis Tamamlandı                    ")
        print("==================================================")
    }

    public static func runModePoolDiagnostic() {
        do {
            let url = try HiDPIModePoolDiagnostic.writeMarkdownReport()
            let summary = HiDPIModePoolDiagnostic.collectSummary()
            print("==================================================")
            print("      AmbientSync HiDPI Mode Pool Diagnostic      ")
            print("==================================================")
            print("Report written: \(url.path)")
            print("Target display: \(summary.targetDisplay?.displayName ?? "unavailable")")
            print("Default mode count: \(summary.defaultModes.count)")
            print("duplicateLowResolutionModes=true mode count: \(summary.duplicateModes.count)")
            print("HiDPI count: \(summary.duplicateModes.filter { $0.isHiDPI }.count)")
            print("Perfect QHD in default list: \(summary.defaultModes.contains(where: NativeDisplayModeReader.isPerfectQHDHiDPIMode) ? "YES" : "NO")")
            print("Perfect QHD in duplicateLowResolutionModes=true list: \(summary.duplicateModes.contains(where: NativeDisplayModeReader.isPerfectQHDHiDPIMode) ? "YES" : "NO")")
            if let target = summary.targetDisplay, let currentMode = CGDisplayCopyDisplayMode(target.displayID) {
                let activePerfectQHD = currentMode.width == 2560 &&
                    currentMode.height == 1440 &&
                    currentMode.pixelWidth == 5120 &&
                    currentMode.pixelHeight == 2880 &&
                    abs(currentMode.refreshRate - 100.0) < 0.1
                print("Active mode Perfect QHD: \(activePerfectQHD ? "YES" : "NO")")
            }
        } catch {
            print("Mode pool diagnostic failed: \(error.localizedDescription)")
        }
    }
}
