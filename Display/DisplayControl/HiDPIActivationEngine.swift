import CoreGraphics
import Foundation

public struct HiDPIActivationSnapshot {
    public let activeModeDescription: String
    public let defaultModeCount: Int
    public let duplicateModeCount: Int
    public let hiDPIModeCount: Int
    public let hasPerfectQHD: Bool
    public let has5120Backing: Bool
    public let has100HzHiDPICandidate: Bool
    public let systemProfilerSummary: String
}

public struct HiDPIActivationExperimentResult {
    public let title: String
    public let before: HiDPIActivationSnapshot
    public let after: HiDPIActivationSnapshot
    public let operationResult: String
    public let rollbackResult: String
    public let changedModePool: Bool
    public let perfectQHDAppeared: Bool
}

public struct HiDPIActivationSpikeResult {
    public let reportURL: URL
    public let perfectQHDAppeared: Bool
    public let appliedPerfectQHD: Bool
    public let classification: String
}

@MainActor
public final class HiDPIActivationEngine {
    private static let reportPath = "docs/generated/hidpi_activation_engine_spike.md"

    public static func runExperimentalSpike() async -> HiDPIActivationSpikeResult {
        let reportURL = HiDPIReportPaths.reportURL(reportPath)

        var lines: [String] = []
        lines.append("# HiDPI Activation Engine Spike")
        lines.append("")
        lines.append("Generated at: \(timestamp())")
        lines.append("")
        lines.append("## Status")
        lines.append("- Disabled. Previous public activation candidates did not create Perfect QHD and must not be retried.")
        lines.append("- Removed candidates: soft refresh, 100Hz/60Hz toggle, CoreGraphics current-mode transaction, arrangement no-op transaction.")
        lines.append("- No live display configuration call was made.")
        write(lines, to: reportURL)
        return HiDPIActivationSpikeResult(
            reportURL: reportURL,
            perfectQHDAppeared: false,
            appliedPerfectQHD: false,
            classification: "Public activation experiments disabled after negative result"
        )

    }

    private static func finish(
        lines inputLines: [String],
        results: [HiDPIActivationExperimentResult],
        reportURL: URL,
        displayID: CGDirectDisplayID
    ) -> HiDPIActivationSpikeResult {
        var lines = inputLines
        let changed = results.filter(\.changedModePool).map(\.title)
        let perfectAppeared = results.contains(where: \.perfectQHDAppeared)
        let finalMode = NativeDisplayModeReader.findPerfectQHDHiDPIMode(for: displayID)
        var appliedPerfectQHD = false

        lines.append("## 9. Hangi deney mode pool'u değiştirdi?")
        if changed.isEmpty {
            lines.append("- Hiçbir deney mode pool sayımlarını veya Perfect QHD varlığını değiştirmedi.")
        } else {
            for title in changed {
                lines.append("- \(title)")
            }
        }
        lines.append("")

        lines.append("## 10. Perfect QHD oluştu mu?")
        lines.append("- \(perfectAppeared ? "Evet" : "Hayır")")
        lines.append("")

        lines.append("## 11. Oluştuysa AmbientSync bunu uygulayabildi mi?")
        if let finalMode {
            let applyResult = HiDPIModeApplier.applyMode(displayID: displayID, targetMode: finalMode)
            switch applyResult {
            case .success(let message):
                lines.append("- Evet: \(message)")
                appliedPerfectQHD = true
            case .noChangeNeeded:
                lines.append("- Evet: ekran zaten Perfect QHD modundaydı.")
                appliedPerfectQHD = true
            case .failure(let reason):
                lines.append("- Hayır: \(reason)")
            }
        } else {
            lines.append("- Uygulanmadı; Perfect QHD mode pool'da oluşmadı.")
        }
        lines.append("")

        lines.append("## 12. Oluşmadıysa public API yeterli değil mi?")
        if perfectAppeared {
            lines.append("- Bu çalıştırmada en az bir public/düşük riskli deney mode pool'u Perfect QHD için aktive etti.")
        } else {
            lines.append("- Bu çalıştırmada kullanılan public CoreGraphics refresh/transaction denemeleri Perfect QHD mode pool'u üretmedi.")
        }
        lines.append("")

        lines.append("## 13. Private/runtime activation ihtimali")
        lines.append("- SkyLight, CGS, SLS veya CoreDisplay private sembolleri kullanılmadı.")
        lines.append("- Public deneyler sonuç vermezse BetterDisplay'in runtime activation adımı private display services veya farklı bir WindowServer reinitialize yolu kullanıyor olabilir.")
        lines.append("")

        lines.append("## 14. Sonraki önerilen adım")
        if perfectAppeared {
            lines.append("- Mode pool'u değiştiren deney izole edilmeli ve yalnızca o düşük riskli yol, ayrı kullanıcı onaylı activation akışına dönüştürülmeli.")
        } else {
            lines.append("- Public API spike sonucu negatifse Activation Engine için daha düşük seviyeli runtime reinitialize araştırması ayrı risk kaydıyla planlanmalı.")
        }
        lines.append("- Programatik sleep/wake, disconnect simulate, virtual/dummy/mirror ve private API bu spike dışında bırakıldı.")

        write(lines, to: reportURL)
        return HiDPIActivationSpikeResult(
            reportURL: reportURL,
            perfectQHDAppeared: perfectAppeared,
            appliedPerfectQHD: appliedPerfectQHD,
            classification: perfectAppeared ? "Public activation path found" : "Public activation experiments did not activate Perfect QHD"
        )
    }

    private static func runSoftModePoolRefresh(displayID: CGDirectDisplayID) async -> HiDPIActivationExperimentResult {
        let before = snapshot(for: displayID)
        _ = NativeDisplayModeReader.getDefaultModes(for: displayID)
        _ = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        _ = CGDisplayCopyDisplayMode(displayID)
        await shortDelay()
        _ = NativeDisplayModeReader.getDefaultModes(for: displayID)
        _ = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        let after = snapshot(for: displayID)
        return result(
            title: "Deney 1 sonucu",
            before: before,
            after: after,
            operation: "Soft mode pool refresh tamamlandı.",
            rollback: "Rollback gerekmedi."
        )
    }

    private static func runSafeModeToggle(displayID: CGDirectDisplayID, title: String) async -> HiDPIActivationExperimentResult {
        let before = snapshot(for: displayID)
        guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
            return result(title: title, before: before, after: snapshot(for: displayID), operation: "Aktif mod okunamadı.", rollback: "Rollback yapılmadı.")
        }

        let modes = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        guard let normal60 = normalQHDMode(in: modes, refresh: 60),
              let normal100 = normalQHDMode(in: modes, refresh: 100) else {
            return result(title: title, before: before, after: snapshot(for: displayID), operation: "Güvenli normal QHD 60Hz/100Hz mod çifti bulunamadı.", rollback: "Rollback gerekmedi.")
        }

        let switchResult = configure(displayID: displayID, mode: normal60.cgMode)
        guard switchResult == .success else {
            return result(title: title, before: before, after: snapshot(for: displayID), operation: "60Hz normal QHD geçişi başarısız: \(switchResult.rawValue)", rollback: "Rollback gerekmedi.")
        }

        await twoSecondDelay()

        let returnResult = configure(displayID: displayID, mode: normal100.cgMode)
        let rollbackText: String
        if returnResult == .success {
            rollbackText = "100Hz normal QHD moda geri dönüldü."
        } else {
            let rollbackResult = configure(displayID: displayID, mode: currentMode)
            rollbackText = "100Hz normal QHD dönüşü başarısız: \(returnResult.rawValue). Saved mode rollback: \(rollbackResult.rawValue)."
        }

        await shortDelay()
        let after = snapshot(for: displayID)
        return result(title: title, before: before, after: after, operation: "Normal QHD 100Hz -> 60Hz -> 100Hz geçişi denendi.", rollback: rollbackText)
    }

    private static func runDisplayConfigurationTransaction(displayID: CGDirectDisplayID) async -> HiDPIActivationExperimentResult {
        let before = snapshot(for: displayID)
        guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
            return result(title: "Deney 4 sonucu", before: before, after: snapshot(for: displayID), operation: "Aktif mod okunamadı.", rollback: "Rollback yapılmadı.")
        }

        let configureResult = configure(displayID: displayID, mode: currentMode)
        await shortDelay()
        let after = snapshot(for: displayID)
        return result(
            title: "Deney 4 sonucu",
            before: before,
            after: after,
            operation: "Mevcut listelenen normal mode ile CoreGraphics display configuration transaction commit edildi: \(configureResult.rawValue).",
            rollback: configureResult == .success ? "Rollback gerekmedi." : "Transaction başarısız; display state değişmedi."
        )
    }

    private static func runArrangementNoOpTransaction(displayID: CGDirectDisplayID) async -> HiDPIActivationExperimentResult {
        let before = snapshot(for: displayID)
        let bounds = CGDisplayBounds(displayID)
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite else {
            return result(title: "Deney 5 sonucu", before: before, after: snapshot(for: displayID), operation: "Mevcut arrangement okunamadı.", rollback: "No-op transaction atlandı.")
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return result(title: "Deney 5 sonucu", before: before, after: snapshot(for: displayID), operation: "Display configuration başlatılamadı.", rollback: "No-op transaction atlandı.")
        }

        let originResult = CGConfigureDisplayOrigin(config, displayID, Int32(bounds.origin.x), Int32(bounds.origin.y))
        guard originResult == .success else {
            CGCancelDisplayConfiguration(config)
            return result(title: "Deney 5 sonucu", before: before, after: snapshot(for: displayID), operation: "Aynı origin ile no-op arrangement güvenli commit edilemedi: \(originResult.rawValue)", rollback: "Transaction iptal edildi.")
        }

        let completeResult = CGCompleteDisplayConfiguration(config, .forSession)
        if completeResult != .success {
            CGCancelDisplayConfiguration(config)
        }

        await shortDelay()
        let after = snapshot(for: displayID)
        return result(
            title: "Deney 5 sonucu",
            before: before,
            after: after,
            operation: "Aynı display origin ile arrangement no-op transaction denendi: \(completeResult.rawValue).",
            rollback: completeResult == .success ? "Rollback gerekmedi; origin değiştirilmedi." : "Transaction başarısız veya iptal edildi."
        )
    }

    private static func normalQHDMode(in modes: [PhysicalDisplayMode], refresh: Double) -> PhysicalDisplayMode? {
        modes.first {
            $0.width == HiDPIOverrideReferenceStore.targetLogicalWidth &&
                $0.height == HiDPIOverrideReferenceStore.targetLogicalHeight &&
                $0.pixelWidth == HiDPIOverrideReferenceStore.targetLogicalWidth &&
                $0.pixelHeight == HiDPIOverrideReferenceStore.targetLogicalHeight &&
                !$0.isHiDPI &&
                abs($0.refreshRate - refresh) < 0.1
        }
    }

    private static func configure(displayID: CGDirectDisplayID, mode: CGDisplayMode) -> CGError {
        guard CGDisplayIsBuiltin(displayID) == 0 else { return .failure }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return .failure
        }
        let configureError = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        guard configureError == .success else {
            CGCancelDisplayConfiguration(config)
            return configureError
        }
        let completeError = CGCompleteDisplayConfiguration(config, .forSession)
        if completeError != .success {
            CGCancelDisplayConfiguration(config)
        }
        return completeError
    }

    private static func snapshot(for displayID: CGDirectDisplayID) -> HiDPIActivationSnapshot {
        let defaultModes = NativeDisplayModeReader.getDefaultModes(for: displayID)
        let duplicateModes = NativeDisplayModeReader.getHiDPIApplyCandidateModes(for: displayID)
        let current = CGDisplayCopyDisplayMode(displayID)
        let activeDescription: String
        if let current {
            let hiDPI = current.pixelWidth > current.width || current.pixelHeight > current.height
            let strong = current.pixelWidth == current.width * 2 && current.pixelHeight == current.height * 2
            let perfect = current.width == HiDPIOverrideReferenceStore.targetLogicalWidth &&
                current.height == HiDPIOverrideReferenceStore.targetLogicalHeight &&
                current.pixelWidth == HiDPIOverrideReferenceStore.targetBackingWidth &&
                current.pixelHeight == HiDPIOverrideReferenceStore.targetBackingHeight &&
                abs(current.refreshRate - HiDPIOverrideReferenceStore.targetRefreshRate) < 0.1
            activeDescription = String(
                format: "%dx%d logical / %dx%d pixel @ %.2fHz | HiDPI:%@ | strong:%@ | PerfectQHD:%@",
                current.width,
                current.height,
                current.pixelWidth,
                current.pixelHeight,
                current.refreshRate,
                hiDPI ? "true" : "false",
                strong ? "true" : "false",
                perfect ? "true" : "false"
            )
        } else {
            activeDescription = "unavailable"
        }

        return HiDPIActivationSnapshot(
            activeModeDescription: activeDescription,
            defaultModeCount: defaultModes.count,
            duplicateModeCount: duplicateModes.count,
            hiDPIModeCount: duplicateModes.filter(\.isHiDPI).count,
            hasPerfectQHD: duplicateModes.contains(where: NativeDisplayModeReader.isPerfectQHDHiDPIMode),
            has5120Backing: duplicateModes.contains { $0.pixelWidth == 5120 && $0.pixelHeight == 2880 },
            has100HzHiDPICandidate: duplicateModes.contains { $0.isHiDPI && abs($0.refreshRate - 100.0) < 0.1 },
            systemProfilerSummary: systemProfilerSummary()
        )
    }

    private static func result(
        title: String,
        before: HiDPIActivationSnapshot,
        after: HiDPIActivationSnapshot,
        operation: String,
        rollback: String
    ) -> HiDPIActivationExperimentResult {
        let changed = before.defaultModeCount != after.defaultModeCount ||
            before.duplicateModeCount != after.duplicateModeCount ||
            before.hiDPIModeCount != after.hiDPIModeCount ||
            before.hasPerfectQHD != after.hasPerfectQHD ||
            before.has5120Backing != after.has5120Backing
        return HiDPIActivationExperimentResult(
            title: title,
            before: before,
            after: after,
            operationResult: operation,
            rollbackResult: rollback,
            changedModePool: changed,
            perfectQHDAppeared: !before.hasPerfectQHD && after.hasPerfectQHD
        )
    }

    private static func appendExperiment(_ result: HiDPIActivationExperimentResult, number: Int, to lines: inout [String]) {
        lines.append("## \(number). \(result.title)")
        lines.append("- İşlem sonucu: \(result.operationResult)")
        lines.append("- Rollback sonucu: \(result.rollbackResult)")
        lines.append("- Mode pool değişti: \(result.changedModePool)")
        lines.append("- Perfect QHD oluştu: \(result.perfectQHDAppeared)")
        lines.append("")
        lines.append("### Before")
        appendSnapshot(result.before, to: &lines)
        lines.append("")
        lines.append("### After")
        appendSnapshot(result.after, to: &lines)
        lines.append("")
    }

    private static func appendSkippedExperiments(startingAt number: Int, to lines: inout [String]) {
        for index in number...8 {
            lines.append("## \(index). Deney \(index - 3) sonucu")
            lines.append("- Önceki deney Perfect QHD mode pool'u oluşturduğu için kalan deneyler çalıştırılmadı.")
            lines.append("")
        }
    }

    private static func appendSnapshot(_ snapshot: HiDPIActivationSnapshot, to lines: inout [String]) {
        lines.append("- Active mode: \(snapshot.activeModeDescription)")
        lines.append("- Default mode count: \(snapshot.defaultModeCount)")
        lines.append("- duplicateLowResolutionModes=true count: \(snapshot.duplicateModeCount)")
        lines.append("- HiDPI mode count: \(snapshot.hiDPIModeCount)")
        lines.append("- Perfect QHD var: \(snapshot.hasPerfectQHD)")
        lines.append("- 5120x2880 backing mode var: \(snapshot.has5120Backing)")
        lines.append("- 100Hz HiDPI candidate var: \(snapshot.has100HzHiDPICandidate)")
        lines.append("- system_profiler: \(snapshot.systemProfilerSummary)")
    }

    private static func overrideValidationSummary() -> [String] {
        var lines: [String] = []
        let expected = "127e69ab6970328c605de85b85f04769febe47077518a2befc4a2273f42000a6"
        if let systemRecord = try? HiDPIOverrideReferenceStore.systemOverrideRecord() {
            lines.append("- Sistem override mevcut: true")
            lines.append("- SHA256: \(systemRecord.sha256)")
            lines.append("- Beklenen SHA256 ile aynı: \(systemRecord.sha256 == expected)")
            lines.append("- scale-resolutions var: \(systemRecord.hasScaleResolutionsKey)")
            lines.append("- 5120x2880 normal kayıt var: \(systemRecord.hasPerfectQHDNormalRecord)")
            lines.append("- 5120x2880 HiDPI/flexible kayıt var: \(systemRecord.hasPerfectQHDHiDPIRecord)")
        } else {
            lines.append("- Sistem override mevcut: false")
        }
        return lines
    }

    private static func systemProfilerSummary() -> String {
        let output = shellOutput("/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null")
        guard let range = output.range(of: "LS32D60xU:") else {
            return "Samsung LS32D60xU block not found"
        }
        let block = output[range.lowerBound...].split(separator: "\n").prefix(8).joined(separator: " | ")
        return block.replacingOccurrences(of: "  ", with: " ")
    }

    private static func shellOutput(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return "command failed: \(error.localizedDescription)"
        }
    }

    private static func shortDelay() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private static func twoSecondDelay() async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func write(_ lines: [String], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            print("HiDPIActivationEngine report written: \(url.path)")
        } catch {
            fputs("HiDPIActivationEngine report write failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
