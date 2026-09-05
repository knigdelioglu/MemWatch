import AppKit
import CoreGraphics
import Foundation

actor DDCRawBrightnessProbeDiagnostic {
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

    func run(preferredDisplayKey: String? = nil) async -> DDCRawBrightnessProbeSummary {
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

        let beforeSample = readBrightnessSample(displayIndex: ddcTarget.displayIndex)
        let requestedRawMax = beforeSample.rawMax
        let writeResult = await setBrightnessRawMax(displayIndex: ddcTarget.displayIndex, requestedRawMax: requestedRawMax)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let afterSample = readBrightnessSample(displayIndex: ddcTarget.displayIndex)
        let normalizedAfterPercent: Int? = {
            guard let rawAfter = afterSample.rawCurrent, let rawMax = beforeSample.rawMax else { return nil }
            return DDCBrightnessScale.uiPercent(fromRawCurrent: rawAfter, rawMax: rawMax)
        }()
        let matchedMax = DDCBrightnessScale.isMatched(rawAfter: afterSample.rawCurrent, computedRawTarget: requestedRawMax)

        var diagnosis: [String] = []
        var notes: [String] = []

        if !writeResult.success {
            diagnosis.append("DDC write failed.")
        } else if matchedMax {
            diagnosis.append("Raw max write matched the monitor readback.")
        } else {
            diagnosis.append("DDC write accepted but readback did not reach the requested raw max.")
            notes.append("DDC write accepted but readback is uncertain; this single mismatch is not proof of a monitor-side limiter.")
        }

        if let rawMax = beforeSample.rawMax, rawMax == 50, let normalizedAfterPercent, (40...55).contains(normalizedAfterPercent) {
            diagnosis = ["DDC readback %46 civarında; tek probe limiter kanıtı değildir. HDR/Eco/Eye Saver/Adaptive Picture/Picture Mode ayarları kontrol edilmeli."]
        }

        return DDCRawBrightnessProbeSummary(
            targetDisplayName: target.displayName,
            displayID: target.displayID,
            displayIndex: ddcTarget.displayIndex,
            vendorID: target.vendorID,
            productID: target.productID,
            serialNumber: target.serialNumber,
            rawCurrentBefore: beforeSample.rawCurrent,
            rawMax: beforeSample.rawMax,
            requestedRawMax: requestedRawMax,
            writeStatus: writeResult.success && matchedMax ? .success : (writeResult.success ? .writeAcceptedReadbackUncertain : .writeFailed),
            rawAfter: afterSample.rawCurrent,
            normalizedAfterPercent: normalizedAfterPercent,
            matchedMax: matchedMax,
            diagnosis: diagnosis,
            notes: notes
        )
    }

    func writeDiagnosticReport(summary: DDCRawBrightnessProbeSummary) throws -> URL {
        try DDCRawBrightnessProbeReporter.writeMarkdownReport(summary: summary)
    }

    private func makeUnknownSummary(
        targetDisplayName: String,
        displayID: CGDirectDisplayID,
        displayIndex: String?,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32?,
        notes: [String]
    ) -> DDCRawBrightnessProbeSummary {
        DDCRawBrightnessProbeSummary(
            targetDisplayName: targetDisplayName,
            displayID: displayID,
            displayIndex: displayIndex,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            rawCurrentBefore: nil,
            rawMax: nil,
            requestedRawMax: nil,
            writeStatus: .writeFailed,
            rawAfter: nil,
            normalizedAfterPercent: nil,
            matchedMax: false,
            diagnosis: ["unknown"],
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

    private func readBrightnessSample(displayIndex: String) -> DDCBrightnessRawSample {
        guard let executable = m1ddcExecutableURL() else {
            return DDCBrightnessRawSample(rawCurrent: nil, rawMax: nil, available: false, output: "m1ddc not found")
        }

        guard let output = runProcess(executable: executable.path, arguments: ["display", displayIndex, "get", "luminance"]) else {
            return DDCBrightnessRawSample(rawCurrent: nil, rawMax: nil, available: false, output: "Failed to execute brightness read")
        }

        return DDCBrightnessParsing.parseRawSample(from: output)
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
}
