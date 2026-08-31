import Foundation

enum EDIDParser {
    private static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    static func parse(_ data: Data) -> EDIDParseResult {
        var notes: [String] = []
        let rawByteCount = data.count
        let sha256 = EDIDHash.sha256Hex(from: data)

        let headerMatches = matchesHeader(data)
        let manufacturerCode = parseManufacturerCode(from: data)
        let productCode = readUInt16LE(data, offset: 10)
        let serialNumber = readUInt32LE(data, offset: 12)
        let manufactureWeek = readUInt8(data, offset: 16)
        let manufactureYear = readUInt8(data, offset: 17).map { UInt16(1990 + Int($0)) }
        let horizontalSizeCm = readUInt8(data, offset: 21)
        let verticalSizeCm = readUInt8(data, offset: 22)
        let displayName = parseDisplayName(from: data)
        let preferredTimingSummary = parsePreferredTimingSummary(from: data)

        if rawByteCount == 0 {
            notes.append("EDID data unavailable")
        } else if rawByteCount < 128 {
            notes.append("EDID shorter than 128 bytes")
        } else if !headerMatches {
            notes.append("EDID header mismatch")
        }

        if manufacturerCode == nil {
            notes.append("Manufacturer code unreadable")
        }

        if displayName == nil {
            notes.append("Display name descriptor not found")
        }

        if preferredTimingSummary == nil {
            notes.append("Preferred timing descriptor not found")
        }

        let status: EDIDReadStatus
        if rawByteCount == 0 {
            status = .unavailable
        } else if rawByteCount < 128 {
            status = .partial
        } else if !headerMatches {
            status = .invalid
        } else {
            status = .available
        }

        let info = EDIDInfo(
            rawByteCount: rawByteCount,
            sha256: sha256,
            manufacturerCode: manufacturerCode,
            productCode: productCode,
            serialNumber: serialNumber,
            manufactureWeek: manufactureWeek,
            manufactureYear: manufactureYear,
            displayName: displayName,
            preferredTimingSummary: preferredTimingSummary,
            horizontalSizeCm: horizontalSizeCm,
            verticalSizeCm: verticalSizeCm,
            matchConfidence: .unavailable,
            status: status,
            notes: notes
        )

        return EDIDParseResult(info: info)
    }

    private static func matchesHeader(_ data: Data) -> Bool {
        guard data.count >= header.count else { return false }
        for (index, byte) in header.enumerated() where data[index] != byte {
            return false
        }
        return true
    }

    private static func parseManufacturerCode(from data: Data) -> String? {
        guard let raw = readUInt16BE(data, offset: 8) else { return nil }
        let letters = [
            UInt8((raw >> 10) & 0x1F),
            UInt8((raw >> 5) & 0x1F),
            UInt8(raw & 0x1F)
        ]

        let decoded = letters.map { value -> Character? in
            guard (1...26).contains(value) else { return nil }
            return Character(UnicodeScalar(UInt8(64 + value)))
        }

        guard decoded.allSatisfy({ $0 != nil }) else { return nil }
        return String(decoded.compactMap { $0 })
    }

    private static func parseDisplayName(from data: Data) -> String? {
        let descriptors = descriptorBlocks(from: data)
        for descriptor in descriptors where descriptor.count == 18 {
            guard readUInt16LE(descriptor, offset: 0) == 0 else { continue }
            guard readUInt8(descriptor, offset: 3) == 0xFC else { continue }
            let textBytes = Array(descriptor.dropFirst(5))
            let text = sanitizeDescriptorText(textBytes)
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func parsePreferredTimingSummary(from data: Data) -> String? {
        for descriptor in descriptorBlocks(from: data) where descriptor.count == 18 {
            guard let pixelClock = readUInt16LE(descriptor, offset: 0), pixelClock > 0 else { continue }
            guard let horizontalActive = detailedTimingHorizontalActive(descriptor),
                  let verticalActive = detailedTimingVerticalActive(descriptor) else {
                continue
            }

            let summary: String
            if let refreshRate = detailedTimingRefreshRate(descriptor) {
                summary = String(format: "%dx%d @ %.2fHz", horizontalActive, verticalActive, refreshRate)
            } else {
                summary = "\(horizontalActive)x\(verticalActive)"
            }
            return summary
        }
        return nil
    }

    private static func descriptorBlocks(from data: Data) -> [Data] {
        guard data.count >= 54 else { return [] }
        let end = min(data.count, 126)
        var descriptors: [Data] = []
        var index = 54
        while index + 18 <= end {
            descriptors.append(data[index..<(index + 18)])
            index += 18
        }
        return descriptors
    }

    private static func sanitizeDescriptorText(_ bytes: [UInt8]) -> String {
        let text = String(bytes: bytes, encoding: .ascii) ?? ""
        return text
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detailedTimingHorizontalActive(_ descriptor: Data) -> Int? {
        guard descriptor.count == 18,
              let hActiveLsb = readUInt8(descriptor, offset: 2),
              let hBlankLsb = readUInt8(descriptor, offset: 3),
              let hHigh = readUInt8(descriptor, offset: 4) else {
            return nil
        }
        let hActive = Int(hActiveLsb) + Int((hHigh >> 4) & 0x0F) * 256
        let hBlank = Int(hBlankLsb) + Int(hHigh & 0x0F) * 256
        return hActive > 0 && hBlank >= 0 ? hActive : nil
    }

    private static func detailedTimingVerticalActive(_ descriptor: Data) -> Int? {
        guard descriptor.count == 18,
              let vActiveLsb = readUInt8(descriptor, offset: 5),
              let vBlankLsb = readUInt8(descriptor, offset: 6),
              let vHigh = readUInt8(descriptor, offset: 7) else {
            return nil
        }
        let vActive = Int(vActiveLsb) + Int((vHigh >> 4) & 0x0F) * 256
        let vBlank = Int(vBlankLsb) + Int(vHigh & 0x0F) * 256
        return vActive > 0 && vBlank >= 0 ? vActive : nil
    }

    private static func detailedTimingRefreshRate(_ descriptor: Data) -> Double? {
        guard descriptor.count == 18,
              let pixelClockRaw = readUInt16LE(descriptor, offset: 0),
              pixelClockRaw > 0,
              let hActiveLsb = readUInt8(descriptor, offset: 2),
              let hBlankLsb = readUInt8(descriptor, offset: 3),
              let hHigh = readUInt8(descriptor, offset: 4),
              let vActiveLsb = readUInt8(descriptor, offset: 5),
              let vBlankLsb = readUInt8(descriptor, offset: 6),
              let vHigh = readUInt8(descriptor, offset: 7) else {
            return nil
        }

        let hActive = Int(hActiveLsb) + Int((hHigh >> 4) & 0x0F) * 256
        let hBlank = Int(hBlankLsb) + Int(hHigh & 0x0F) * 256
        let vActive = Int(vActiveLsb) + Int((vHigh >> 4) & 0x0F) * 256
        let vBlank = Int(vBlankLsb) + Int(vHigh & 0x0F) * 256
        let hTotal = hActive + hBlank
        let vTotal = vActive + vBlank
        guard hTotal > 0, vTotal > 0 else { return nil }

        let pixelClockHz = Double(pixelClockRaw) * 10_000.0
        return pixelClockHz / Double(hTotal * vTotal)
    }

    private static func readUInt8(_ data: Data, offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[offset]
    }

    private static func readUInt16LE(_ data: Data, offset: Int) -> UInt16? {
        guard let low = readUInt8(data, offset: offset),
              let high = readUInt8(data, offset: offset + 1) else {
            return nil
        }
        return UInt16(low) | (UInt16(high) << 8)
    }

    private static func readUInt16BE(_ data: Data, offset: Int) -> UInt16? {
        guard let high = readUInt8(data, offset: offset),
              let low = readUInt8(data, offset: offset + 1) else {
            return nil
        }
        return (UInt16(high) << 8) | UInt16(low)
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32? {
        guard let b0 = readUInt8(data, offset: offset),
              let b1 = readUInt8(data, offset: offset + 1),
              let b2 = readUInt8(data, offset: offset + 2),
              let b3 = readUInt8(data, offset: offset + 3) else {
            return nil
        }
        return UInt32(b0)
            | (UInt32(b1) << 8)
            | (UInt32(b2) << 16)
            | (UInt32(b3) << 24)
    }
}
