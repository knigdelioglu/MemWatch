import AppKit
import Darwin
import Foundation

enum DisplayDiagnosticRouter {
    static func handleIfRequested() async -> Bool {
        let arguments = CommandLine.arguments

        if arguments.contains("--release-bundle-smoke") {
            runReleaseBundleSmoke()
            return true
        }

        if arguments.contains("--display-discovery-diagnostic") {
            await DisplayDiscoveryDiagnostic.run()
            return true
        }

        if arguments.contains("--diagnostic") {
            HiDPIDiagnostic.run()
            exit(0)
        }

        if arguments.contains("--hidpi-mode-pool-diagnostic") {
            HiDPIDiagnostic.runModePoolDiagnostic()
            exit(0)
        }

        if arguments.contains("--cgs-mode-enumeration") {
            runCGSModeEnumeration()
            return true
        }

        if arguments.contains("--cgs-mode74-without-betterdisplay") {
            runCGSMode74Verification()
            return true
        }

        if arguments.contains("--cgs-mode74-apply-experiment") {
            runCGSApplyExperiment()
            return true
        }

        if let index = arguments.firstIndex(of: "--hidpi-system-snapshot") {
            guard arguments.indices.contains(index + 1) else {
                fputs("Missing output directory after --hidpi-system-snapshot\n", stderr)
                exit(2)
            }

            do {
                try HiDPISystemSnapshotReporter.writeSnapshot(
                    to: URL(fileURLWithPath: arguments[index + 1])
                )
                print("HiDPI system snapshot written: \(arguments[index + 1])")
                exit(0)
            } catch {
                fputs("HiDPI system snapshot failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if arguments.contains("--hidpi-activation-spike") {
            let result = await HiDPIActivationEngine.runExperimentalSpike()
            print("HiDPI activation spike report written: \(result.reportURL.path)")
            print("Classification: \(result.classification)")
            print("Perfect QHD appeared: \(result.perfectQHDAppeared)")
            print("Applied Perfect QHD: \(result.appliedPerfectQHD)")
            exit(0)
        }

        return false
    }

    private static func runReleaseBundleSmoke() {
        do {
            let record = try HiDPIOverrideReferenceStore.bundledReferenceRecord()
            guard record.vendorID == HiDPIOverrideReferenceStore.targetVendorID,
                  record.productID == HiDPIOverrideReferenceStore.targetProductID,
                  HiDPIOverrideReferenceStore.perfectQHDRecordsPresent(in: record) else {
                fputs("Release bundle resource validation failed\n", stderr)
                exit(1)
            }
            print("Release bundle smoke check passed")
            exit(0)
        } catch {
            fputs("Release bundle smoke check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runCGSModeEnumeration() {
        do {
            let summary = try CGSModeEnumerationDiagnostic.runEnumeration()
            print("CGS mode enumeration report written: \(summary.reportURL.path)")
            print("CGS current mode id: \(summary.currentModeID.map(String.init) ?? "unavailable")")
            print("CGS mode count: \(summary.cgsModeCount)")
            print("Public duplicate count: \(summary.publicDuplicateModeCount)")
            exit(0)
        } catch {
            fputs("CGS mode enumeration failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runCGSMode74Verification() {
        do {
            let summary = try CGSModeEnumerationDiagnostic.runWithoutBetterDisplayVerification()
            print("CGS mode 74 check report written: \(summary.reportURL.path)")
            print("CGS current mode id: \(summary.currentModeID.map(String.init) ?? "unavailable")")
            print("CGS mode count: \(summary.cgsModeCount)")
            print("Public duplicate count: \(summary.publicDuplicateModeCount)")
            print("Mode 74 present: \(summary.mode74 != nil)")
            print("Mode 74 perfect QHD: \(summary.mode74IsPerfectQHD)")
            exit(0)
        } catch {
            fputs("CGS mode 74 check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runCGSApplyExperiment() {
        do {
            let summary = try CGSModeEnumerationDiagnostic.runMode56Then74ApplyExperiment()
            print("CGS apply experiment report written: \(summary.reportURL.path)")
            print("Before mode id: \(summary.initialModeID.map(String.init) ?? "unavailable")")
            print("Mode 56 verified: \(summary.mode56Verified)")
            print("Mode 74 verified: \(summary.mode74Verified)")
            print("Final active mode: \(summary.finalSummary.activeModeDescription)")
            print("Success: \(summary.success)")
            exit(summary.success ? 0 : 1)
        } catch {
            fputs("CGS apply experiment failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
