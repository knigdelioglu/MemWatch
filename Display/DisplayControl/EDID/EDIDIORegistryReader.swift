import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

final class EDIDIORegistryReader {
    private struct DisplayFingerprint {
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32?
    }

    private struct Candidate {
        let serviceName: String
        let fingerprint: DisplayFingerprint
        let displayName: String?
        let edidData: Data?
    }

    private struct MatchedCandidate {
        let candidate: Candidate
        let matchConfidence: EDIDMatchConfidence
        let score: Int
    }

    func readDiagnosticSummary(for displayID: CGDirectDisplayID) -> EDIDDiagnosticSummary {
        let targetFingerprint = DisplayFingerprint(
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serialNumber: {
                let serial = CGDisplaySerialNumber(displayID)
                return serial == 0 ? nil : serial
            }()
        )
        let targetName = displayName(for: displayID)

        guard CGDisplayIsBuiltin(displayID) == 0 else {
            return makeSummary(
                displayID: displayID,
                targetName: targetName,
                targetFingerprint: targetFingerprint,
                edidInfo: nil,
                matchConfidence: .unavailable,
                status: .unavailable,
                notes: ["Built-in display ignored"]
            )
        }

        let candidates = collectCandidates()
        let matches = candidates.compactMap { match(candidate: $0, target: targetFingerprint) }
        guard let bestScore = matches.map(\.score).max() else {
            return makeSummary(
                displayID: displayID,
                targetName: targetName,
                targetFingerprint: targetFingerprint,
                edidInfo: nil,
                matchConfidence: .unavailable,
                status: .unavailable,
                notes: ["No matching IODisplayConnect or AppleDisplay node found"]
            )
        }

        let bestMatches = matches.filter { $0.score == bestScore }
        guard bestMatches.count == 1, let selected = bestMatches.first else {
            return makeSummary(
                displayID: displayID,
                targetName: targetName,
                targetFingerprint: targetFingerprint,
                edidInfo: nil,
                matchConfidence: .ambiguous,
                status: .ambiguous,
                notes: ["Multiple IORegistry display nodes matched the target fingerprint"]
            )
        }

        guard let edidData = selected.candidate.edidData, !edidData.isEmpty else {
            return makeSummary(
                displayID: displayID,
                targetName: targetName,
                targetFingerprint: targetFingerprint,
                edidInfo: nil,
                matchConfidence: selected.matchConfidence,
                status: .unavailable,
                notes: [
                    "Matching IORegistry node found: \(selected.candidate.serviceName)",
                    "IODisplayEDID property missing"
                ]
            )
        }

        let parsed = EDIDParser.parse(edidData)
        let parsedInfo = parsed.info
        let info = EDIDInfo(
            rawByteCount: parsedInfo.rawByteCount,
            sha256: parsedInfo.sha256,
            manufacturerCode: parsedInfo.manufacturerCode,
            productCode: parsedInfo.productCode,
            serialNumber: parsedInfo.serialNumber,
            manufactureWeek: parsedInfo.manufactureWeek,
            manufactureYear: parsedInfo.manufactureYear,
            displayName: parsedInfo.displayName,
            preferredTimingSummary: parsedInfo.preferredTimingSummary,
            horizontalSizeCm: parsedInfo.horizontalSizeCm,
            verticalSizeCm: parsedInfo.verticalSizeCm,
            matchConfidence: selected.matchConfidence,
            status: parsedInfo.status,
            notes: parsedInfo.notes + [
                "Matching IORegistry node: \(selected.candidate.serviceName)",
                selected.candidate.displayName.map { "Registry display name: \($0)" } ?? "Registry display name unavailable"
            ]
        )

        return makeSummary(
            displayID: displayID,
            targetName: targetName,
            targetFingerprint: targetFingerprint,
            edidInfo: info,
            matchConfidence: selected.matchConfidence,
            status: info.status,
            notes: info.notes
        )
    }

    private func makeSummary(
        displayID: CGDirectDisplayID,
        targetName: String,
        targetFingerprint: DisplayFingerprint,
        edidInfo: EDIDInfo?,
        matchConfidence: EDIDMatchConfidence,
        status: EDIDReadStatus,
        notes: [String]
    ) -> EDIDDiagnosticSummary {
        EDIDDiagnosticSummary(
            displayID: displayID,
            targetDisplayName: targetName,
            targetVendorID: targetFingerprint.vendorID,
            targetProductID: targetFingerprint.productID,
            targetSerialNumber: targetFingerprint.serialNumber,
            edidInfo: edidInfo,
            matchConfidence: matchConfidence,
            status: status,
            notes: notes
        )
    }

    private func collectCandidates() -> [Candidate] {
        var unique: [String: Candidate] = [:]
        for className in ["IODisplayConnect", "AppleDisplay"] {
            guard let iterator = makeIterator(for: className) else { continue }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let candidate = candidate(for: service, className: className) else { continue }
                let key = String(service)
                unique[key] = candidate
            }
        }
        return Array(unique.values)
    }

    private func makeIterator(for className: String) -> io_iterator_t? {
        guard let matching = IOServiceMatching(className) else { return nil }
        var iterator = io_iterator_t()
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }
        return iterator
    }

    private func candidate(for service: io_object_t, className: String) -> Candidate? {
        guard let info = IODisplayCreateInfoDictionary(service, 0)?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard let vendorID = uint32Value(info["DisplayVendorID"]),
              let productID = uint32Value(info["DisplayProductID"]) else {
            return nil
        }

        let serialNumber = uint32Value(info["DisplaySerialNumber"])
        let displayName = productName(from: info["DisplayProductName"])
        let edidData = edidData(for: service)

        return Candidate(
            serviceName: "\(className)@\(service)",
            fingerprint: DisplayFingerprint(
                vendorID: vendorID,
                productID: productID,
                serialNumber: serialNumber
            ),
            displayName: displayName,
            edidData: edidData
        )
    }

    private func match(candidate: Candidate, target: DisplayFingerprint) -> MatchedCandidate? {
        guard candidate.fingerprint.vendorID == target.vendorID,
              candidate.fingerprint.productID == target.productID else {
            return nil
        }

        if let targetSerial = target.serialNumber, let candidateSerial = candidate.fingerprint.serialNumber {
            guard candidateSerial == targetSerial else { return nil }
            return MatchedCandidate(candidate: candidate, matchConfidence: .certain, score: 3)
        }

        if target.serialNumber == nil && candidate.fingerprint.serialNumber == nil {
            return MatchedCandidate(candidate: candidate, matchConfidence: .high, score: 2)
        }

        return MatchedCandidate(candidate: candidate, matchConfidence: .medium, score: 1)
    }

    private func edidData(for service: io_object_t) -> Data? {
        guard let property = IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let data = property as? Data {
            return data.isEmpty ? nil : data
        }
        guard CFGetTypeID(property) == CFDataGetTypeID() else { return nil }
        return Data(referencing: unsafeDowncast(property, to: CFData.self))
    }

    private func uint32Value(_ value: Any?) -> UInt32? {
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        if let intValue = value as? Int, intValue >= 0 {
            return UInt32(intValue)
        }
        if let string = value as? String, let intValue = UInt32(string) {
            return intValue
        }
        return nil
    }

    private func productName(from value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dictionary = value as? [String: String] {
            return dictionary.values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        if let dictionary = value as? [String: Any] {
            for candidate in dictionary.values {
                if let string = candidate as? String {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[key] as? NSNumber
            if number?.uint32Value == displayID {
                return screen.localizedName
            }
        }
        return "Display \(displayID)"
    }
}
