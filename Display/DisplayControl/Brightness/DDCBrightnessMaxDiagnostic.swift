import AppKit
import CoreGraphics
import Foundation

actor DDCBrightnessMaxDiagnostic {
    private let m1ddcCandidates = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc",
    ]

    private struct DDCDisplayPartial {
        var displayIndex: String = ""
        var productName: String = ""
        var serial: String?
        var systemUUID: String?
        var ioLocation: String?
    }

    private struct DDCDisplayCandidate: Sendable {
        let displayIndex: String
        let productName: String
        let serial: String?
        let systemUUID: String?
        let ioLocation: String?

        var displayKey: String {
            let identity = (serial?.isEmpty == false ? serial : nil)
                ?? (systemUUID?.isEmpty == false ? systemUUID : nil)
                ?? displayIndex
            return "\(productName)|\(identity)"
        }

        var isLikelyInternal: Bool {
            let lowerName = productName.lowercased()
            let lowerLocation = ioLocation?.lowercased() ?? ""
            return lowerName.contains("built-in") || lowerName.contains("color lcd") || lowerLocation.contains("disp0")
        }
    }

    private struct DDCCommandResult: Sendable {
        let success: Bool
        let output: String
    }

    private struct DDCValueProbe: Sendable {
        let currentValue: Int?
        let maxValue: Int?
        let currentReadAvailable: Bool
        let maxReadAvailable: Bool
        let notes: [String]
    }

    private static let supportedVCPLabelMap: [String: String] = [
        "10": "Brightness",
        "12": "Contrast",
        "14": "Select Color Preset",
        "16": "Red Video Gain",
        "18": "Green Video Gain",
        "1A": "Blue Video Gain",
    ]

    func run(preferredDisplayKey: String? = nil) async -> DDCBrightnessMaxDiagnosticSummary {
        guard let target = try? HiDPITargetDisplayResolver.resolveSamsungS60UDForDiagnostics() else {
            return makeUnknownSummary(
                targetDisplayName: "unavailable",
                displayID: 0,
                displayIndex: nil,
                vendorID: 0,
                productID: 0,
                serialNumber: nil,
                notes: ["Target Samsung display not found"]
            )
        }

        guard let ddcTarget = discoverDDCTarget(preferredDisplayKey: preferredDisplayKey) else {
            return makeUnknownSummary(
                targetDisplayName: target.displayName,
                displayID: target.displayID,
                displayIndex: nil,
                vendorID: target.vendorID,
                productID: target.productID,
                serialNumber: target.serialNumber,
                notes: ["DDC target display not found"]
            )
        }

        let capabilitiesProbe = readDisplayCapabilities()
        let brightnessBefore = probe(displayIndex: ddcTarget.displayIndex, command: "luminance")
        let contrastBefore = probe(displayIndex: ddcTarget.displayIndex, command: "contrast")
        let redProbe = probe(displayIndex: ddcTarget.displayIndex, command: "red")
        let greenProbe = probe(displayIndex: ddcTarget.displayIndex, command: "green")
        let blueProbe = probe(displayIndex: ddcTarget.displayIndex, command: "blue")

        let requestedRawMax = brightnessBefore.maxValue
        let setBrightnessCommandResult = await setBrightnessRawMax(displayIndex: ddcTarget.displayIndex, requestedRawMax: requestedRawMax)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let brightnessAfterProbe = probe(displayIndex: ddcTarget.displayIndex, command: "luminance")
        let brightnessReadbackAfter = brightnessAfterProbe.currentValue
        let brightnessReadbackAfterUIPercent: Int? = {
            guard let rawAfter = brightnessAfterProbe.currentValue, let rawMax = brightnessBefore.maxValue else { return nil }
            return DDCBrightnessScale.uiPercent(fromRawCurrent: rawAfter, rawMax: rawMax)
        }()
        let matchedTarget = DDCBrightnessScale.isMatched(
            rawAfter: brightnessAfterProbe.currentValue,
            computedRawTarget: requestedRawMax
        )
        let writeStatus: M1DDCBrightnessWriteStatus = {
            guard setBrightnessCommandResult.success else { return .writeFailed }
            guard brightnessAfterProbe.currentValue != nil else { return .readbackUnavailable }
            return matchedTarget ? .success : .writeAcceptedButReadbackLimited
        }()
        let setBrightnessSucceeded = writeStatus == .success

        let supportedVCPCodes = Self.supportedVCPCodeList(
            capabilitiesString: capabilitiesProbe.capabilitiesString,
            successfulProbes: [
                ("10", brightnessBefore.currentReadAvailable || brightnessBefore.maxReadAvailable),
                ("12", contrastBefore.currentReadAvailable || contrastBefore.maxReadAvailable),
                ("14", capabilitiesProbe.capabilitiesString?.localizedCaseInsensitiveContains("14") == true),
                ("16", redProbe.currentReadAvailable || redProbe.maxReadAvailable),
                ("18", greenProbe.currentReadAvailable || greenProbe.maxReadAvailable),
                ("1A", blueProbe.currentReadAvailable || blueProbe.maxReadAvailable),
            ]
        )

        let contrastLow = Self.isContrastLow(current: contrastBefore.currentValue, max: contrastBefore.maxValue)
        let possibleLimiter = Self.determineLimiter(
            maxBrightness: brightnessBefore.maxValue,
            setSucceeded: setBrightnessSucceeded,
            brightnessReadbackAfterSet100: brightnessReadbackAfterUIPercent,
            contrastLow: contrastLow
        )

        let diagnosis = Self.buildDiagnosis(
            maxBrightness: brightnessBefore.maxValue,
            setSucceeded: setBrightnessSucceeded,
            brightnessReadbackAfterSet100: brightnessReadbackAfterUIPercent,
            contrastLow: contrastLow
        )

        var notes = capabilitiesProbe.notes
        if capabilitiesProbe.capabilitiesString == nil {
            notes.append("MCCS capabilities string not available through m1ddc on this system")
        }
        if let max = brightnessBefore.maxValue, max != 100 {
            notes.append("DDC brightness max is \(max), so UI percentage mapping may need rescaling")
        }
        if let current = contrastBefore.currentValue, let max = contrastBefore.maxValue, Self.isContrastLow(current: current, max: max) {
            notes.append("Brightness 100 olsa bile contrast düşük olduğu için görüntü sönük algılanabilir.")
        }
        if setBrightnessSucceeded, brightnessReadbackAfterUIPercent == 100, brightnessBefore.maxValue == 100 {
            notes.append("DDC brightness 100 uygulanmış görünüyor; HDR/OSD/Eco/Contrast/Color profile kaynaklı sönüklük ihtimali var.")
        }
        if writeStatus == .writeAcceptedButReadbackLimited {
            notes.append("DDC write accepted but monitor did not change brightness. Possible monitor-side limiter.")
        }

        return DDCBrightnessMaxDiagnosticSummary(
            targetDisplayName: target.displayName,
            displayID: target.displayID,
            displayIndex: ddcTarget.displayIndex,
            vendorID: target.vendorID,
            productID: target.productID,
            serialNumber: target.serialNumber,
            currentBrightnessBefore: brightnessBefore.currentValue,
            maxBrightness: brightnessBefore.maxValue,
            setBrightness100Succeeded: setBrightnessSucceeded,
            brightnessReadbackAfterSet100: brightnessReadbackAfter,
            brightnessReadbackAfterSet100UIPercent: brightnessReadbackAfterUIPercent,
            requestedRawMax: requestedRawMax,
            computedRawTarget: requestedRawMax,
            rawBrightnessBefore: brightnessBefore.currentValue,
            rawBrightnessAfter: brightnessAfterProbe.currentValue,
            matchedTarget: matchedTarget,
            writeStatus: writeStatus,
            currentContrast: contrastBefore.currentValue,
            maxContrast: contrastBefore.maxValue,
            mccsCapabilitiesAvailable: capabilitiesProbe.capabilitiesString != nil,
            mccsCapabilitiesString: capabilitiesProbe.capabilitiesString,
            supportedVCPCodes: supportedVCPCodes,
            possibleBrightnessLimiter: possibleLimiter,
            diagnosis: diagnosis,
            recommendedManualChecks: Self.recommendedManualChecks(
                maxBrightness: brightnessBefore.maxValue,
                setSucceeded: setBrightnessSucceeded,
                readback: brightnessReadbackAfterUIPercent,
                contrastLow: contrastLow
            ),
            notes: notes
        )
    }

    func writeDiagnosticReport(summary: DDCBrightnessMaxDiagnosticSummary) throws -> URL {
        try DDCBrightnessMaxDiagnosticReporter.writeMarkdownReport(summary: summary)
    }

    private func makeUnknownSummary(
        targetDisplayName: String,
        displayID: CGDirectDisplayID,
        displayIndex: String?,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32?,
        notes: [String]
    ) -> DDCBrightnessMaxDiagnosticSummary {
        DDCBrightnessMaxDiagnosticSummary(
            targetDisplayName: targetDisplayName,
            displayID: displayID,
            displayIndex: displayIndex,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            currentBrightnessBefore: nil,
            maxBrightness: nil,
            setBrightness100Succeeded: nil,
            brightnessReadbackAfterSet100: nil,
            brightnessReadbackAfterSet100UIPercent: nil,
            requestedRawMax: nil,
            computedRawTarget: nil,
            rawBrightnessBefore: nil,
            rawBrightnessAfter: nil,
            matchedTarget: nil,
            writeStatus: nil,
            currentContrast: nil,
            maxContrast: nil,
            mccsCapabilitiesAvailable: false,
            mccsCapabilitiesString: nil,
            supportedVCPCodes: [],
            possibleBrightnessLimiter: .unknown,
            diagnosis: ["unknown"],
            recommendedManualChecks: Self.defaultRecommendedManualChecks,
            notes: notes
        )
    }

    private func discoverDDCTarget(preferredDisplayKey: String?) -> DDCDisplayCandidate? {
        let candidates = discoverDDCDisplays()
        if let preferredDisplayKey, let match = candidates.first(where: { $0.displayKey == preferredDisplayKey }) {
            return match
        }

        if let strict = candidates.first(where: { candidate in
            candidate.productName.localizedCaseInsensitiveContains("S60UD")
                || candidate.productName.localizedCaseInsensitiveContains("LS32D60")
                || candidate.productName.localizedCaseInsensitiveContains("Samsung")
        }) {
            return strict
        }

        return candidates.first(where: { $0.productName.localizedCaseInsensitiveContains("Samsung") })
    }

    private func discoverDDCDisplays() -> [DDCDisplayCandidate] {
        guard let output = runProcess(executable: m1ddcExecutableURL()?.path ?? "", arguments: ["display", "list", "detailed"]) else {
            return []
        }

        func normalized(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "(null)" else { return nil }
            return trimmed
        }

        var result: [DDCDisplayCandidate] = []
        var current: DDCDisplayPartial?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") {
                appendCurrent(current, into: &result)
                current = DDCDisplayPartial()
                if let endIndex = line.firstIndex(of: "]") {
                    let index = line[line.index(after: line.startIndex)..<endIndex].trimmingCharacters(in: .whitespaces)
                    current?.displayIndex = String(index)
                }
                continue
            }

            guard var partial = current else { continue }
            if line.hasPrefix("- Product name:") {
                partial.productName = line.replacingOccurrences(of: "- Product name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- Serial:") {
                partial.serial = normalized(line.replacingOccurrences(of: "- Serial:", with: "").trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("- System UUID:") {
                partial.systemUUID = normalized(line.replacingOccurrences(of: "- System UUID:", with: "").trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("- IO Location:") {
                partial.ioLocation = normalized(line.replacingOccurrences(of: "- IO Location:", with: "").trimmingCharacters(in: .whitespaces))
            }
            current = partial
        }

        appendCurrent(current, into: &result)
        return result
    }

    private func appendCurrent(_ partial: DDCDisplayPartial?, into result: inout [DDCDisplayCandidate]) {
        guard let partial else { return }
        guard !partial.displayIndex.isEmpty, !partial.productName.isEmpty else { return }
        let candidate = DDCDisplayCandidate(
            displayIndex: partial.displayIndex,
            productName: partial.productName,
            serial: partial.serial,
            systemUUID: partial.systemUUID,
            ioLocation: partial.ioLocation
        )
        guard !candidate.isLikelyInternal else { return }
        result.append(candidate)
    }

    private func readDisplayCapabilities() -> (capabilitiesString: String?, notes: [String]) {
        guard let executable = m1ddcExecutableURL() else {
            return (nil, ["m1ddc not found"])
        }

        guard let output = runProcess(executable: executable.path, arguments: ["display", "list", "detailed"]) else {
            return (nil, ["Failed to query display list"])
        }

        var capabilitiesString: String?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.contains("capabilit"), let separator = line.range(of: ":") {
                let candidate = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty {
                    capabilitiesString = candidate
                    break
                }
            }
        }

        return (capabilitiesString, [])
    }

    private func probe(displayIndex: String, command: String) -> DDCValueProbe {
        guard let executable = m1ddcExecutableURL() else {
            return DDCValueProbe(currentValue: nil, maxValue: nil, currentReadAvailable: false, maxReadAvailable: false, notes: ["m1ddc not found"])
        }

        let currentResult = runProcess(executable: executable.path, arguments: ["display", displayIndex, "get", command])
        let maxResult = runProcess(executable: executable.path, arguments: ["display", displayIndex, "max", command])

        return DDCValueProbe(
            currentValue: currentResult.flatMap(Self.parseSignedInt(from:)),
            maxValue: maxResult.flatMap(Self.parseSignedInt(from:)),
            currentReadAvailable: currentResult != nil && currentResult.flatMap(Self.parseSignedInt(from:)) != nil,
            maxReadAvailable: maxResult != nil && maxResult.flatMap(Self.parseSignedInt(from:)) != nil,
            notes: []
        )
    }

    private func setBrightnessRawMax(displayIndex: String, requestedRawMax: Int?) async -> DDCCommandResult {
        guard let executable = m1ddcExecutableURL() else {
            return DDCCommandResult(success: false, output: "m1ddc not found")
        }

        guard let requestedRawMax else {
            return DDCCommandResult(success: false, output: "Unable to read raw brightness max")
        }

        guard let output = runProcess(executable: executable.path, arguments: ["display", displayIndex, "set", "luminance", "\(requestedRawMax)"]) else {
            return DDCCommandResult(success: false, output: "Failed to execute brightness set")
        }

        return DDCCommandResult(success: !output.localizedCaseInsensitiveContains("failed"), output: output)
    }

    private func m1ddcExecutableURL() -> URL? {
        m1ddcCandidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runProcess(executable: String, arguments: [String]) -> String? {
        guard !executable.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func parseSignedInt(from output: String) -> Int? {
        let pattern = #"-?\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) else {
            return nil
        }
        guard let range = Range(match.range, in: output) else { return nil }
        return Int(output[range])
    }

    private static func parseHexCodes(from capabilitiesString: String?) -> [String] {
        guard let capabilitiesString else { return [] }
        guard let vcpRange = capabilitiesString.lowercased().range(of: "vcp") else { return [] }
        let suffix = capabilitiesString[vcpRange.lowerBound...]
        let tokens = suffix.split { !$0.isHexDigit }
        return tokens.compactMap { token in
            guard let value = Int(token, radix: 16), (0x00...0xFF).contains(value) else { return nil }
            return String(format: "%02X", value)
        }
    }

    private static func supportedVCPCodeList(
        capabilitiesString: String?,
        successfulProbes: [(code: String, supported: Bool)]
    ) -> [String] {
        var codes = Set(successfulProbes.filter { $0.supported }.map { $0.code.uppercased() })
        codes.formUnion(parseHexCodes(from: capabilitiesString))

        return codes.sorted().map { code in
            let label = knownLabel(for: code) ?? "VCP \(code)"
            return "0x\(code) \(label)"
        }
    }

    private static func knownLabel(for code: String) -> String? {
        supportedVCPLabelMap[code.uppercased()]
    }

    private static func isContrastLow(current: Int?, max: Int?) -> Bool {
        guard let current, let max, max > 0 else { return false }
        return Double(current) < (Double(max) * 0.8)
    }

    private static func determineLimiter(
        maxBrightness: Int?,
        setSucceeded: Bool,
        brightnessReadbackAfterSet100: Int?,
        contrastLow: Bool
    ) -> DDCBrightnessLimiterState {
        if maxBrightness != nil, maxBrightness != 100 {
            return .yes
        }

        guard setSucceeded else {
            return .unknown
        }

        if let brightnessReadbackAfterSet100 {
            if brightnessReadbackAfterSet100 != 100 {
                return .yes
            }
            return contrastLow ? .yes : .no
        }

        return .unknown
    }

    private static func buildDiagnosis(
        maxBrightness: Int?,
        setSucceeded: Bool,
        brightnessReadbackAfterSet100: Int?,
        contrastLow: Bool
    ) -> [String] {
        var diagnosis: [String] = []

        if let maxBrightness, maxBrightness == 50, let brightnessReadbackAfterSet100 {
            if (40...55).contains(brightnessReadbackAfterSet100) {
                diagnosis.append("Monitör DDC parlaklığı %46 civarında sınırlıyor. HDR/Eco/Eye Saver/Adaptive Picture/Picture Mode ayarları kontrol edilmeli.")
            } else if brightnessReadbackAfterSet100 == 100 {
                diagnosis.append("DDC raw mapping doğrulandı; monitör raw max değerini kabul etti.")
            } else if brightnessReadbackAfterSet100 != 100 {
                diagnosis.append("Monitör DDC parlaklığı sınırlıyor olabilir. HDR/Eco/Eye Saver/Adaptive Picture/Picture Mode ayarlarını kontrol et.")
            }
        } else if setSucceeded, let brightnessReadbackAfterSet100, brightnessReadbackAfterSet100 == 100 {
            diagnosis.append("DDC brightness 100 uygulanmış görünüyor. Sönüklük muhtemelen HDR/OSD/Eco/Contrast/Color profile kaynaklı.")
        } else if setSucceeded {
            diagnosis.append("Monitor DDC brightness 100 komutunu kabul etmiyor veya sınırlıyor.")
        } else {
            diagnosis.append("Monitor DDC brightness 100 komutunu kabul etmiyor veya sınırlıyor.")
        }

        if contrastLow {
            diagnosis.append("Contrast düşük; brightness 100 olsa bile görüntü sönük algılanabilir.")
        }

        return diagnosis
    }

    private static func recommendedManualChecks(
        maxBrightness: Int?,
        setSucceeded: Bool,
        readback: Int?,
        contrastLow: Bool
    ) -> [String] {
        var checks = defaultRecommendedManualChecks
        if let maxBrightness = maxBrightness, maxBrightness != 100 {
            checks.insert("DDC brightness UI mapping'ini max \(maxBrightness) üzerinden ölçekle.", at: 0)
        }
        if setSucceeded, readback != 100 {
            checks.insert("Monitor OSD'de brightness clamp veya limit modlarını kontrol et.", at: 0)
        }
        if contrastLow {
            checks.insert("Contrast ayarını yükselt ve tekrar gözle görsel karşılaştırma yap.", at: 0)
        }
        return checks
    }

    private static var defaultRecommendedManualChecks: [String] {
        [
            "Monitor OSD'de Eco / Eye Saver / Adaptive Picture seçeneklerini kapat.",
            "HDR / High Dynamic Range modunu kapatıp tekrar test et.",
            "OS X renk profili ve ICC profilini kontrol et.",
            "Brightness 100 yazıldıktan sonra readback ile panel parlaklığını karşılaştır.",
            "Monitörün kendi OSD brightness / contrast değerlerini manuel olarak doğrula.",
        ]
    }
}
