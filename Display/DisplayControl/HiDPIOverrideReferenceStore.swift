import Foundation
import CryptoKit

public struct HiDPIOverridePlistRecord {
    public let url: URL
    public let data: Data
    public let dictionary: [String: Any]

    public var sha256: String {
        HiDPIOverrideReferenceStore.sha256(data: data)
    }

    public var vendorID: UInt32? {
        HiDPIOverrideReferenceStore.uint32Value(dictionary["DisplayVendorID"])
    }

    public var productID: UInt32? {
        HiDPIOverrideReferenceStore.uint32Value(dictionary["DisplayProductID"])
    }

    public var scaleResolutions: [Data] {
        dictionary["scale-resolutions"] as? [Data] ?? []
    }

    public var scaleResolutionHexStrings: [String] {
        scaleResolutions.map { $0.map { String(format: "%02hhX", $0) }.joined() }
    }

    public var hasScaleResolutionsKey: Bool {
        dictionary["scale-resolutions"] != nil
    }

    public var hasPerfectQHDNormalRecord: Bool {
        scaleResolutionHexStrings.contains(HiDPIOverrideReferenceStore.perfectQHDNormalHex)
    }

    public var hasPerfectQHDHiDPIRecord: Bool {
        scaleResolutionHexStrings.contains(HiDPIOverrideReferenceStore.perfectQHDHiDPIHex)
    }

    public var perfectQHDRecordsPresent: Bool {
        hasPerfectQHDNormalRecord && hasPerfectQHDHiDPIRecord
    }
}

public enum HiDPIOverrideReferenceStoreError: Error, LocalizedError {
    case bundledReferenceMissing
    case fileUnreadable(URL, underlying: Error)
    case invalidPropertyList(URL)

    public var errorDescription: String? {
        switch self {
        case .bundledReferenceMissing:
            return "Bundled reference plist could not be located."
        case .fileUnreadable(let url, let underlying):
            return "Could not read plist at \(url.path): \(underlying.localizedDescription)"
        case .invalidPropertyList(let url):
            return "Invalid plist structure at \(url.path)."
        }
    }
}

public final class HiDPIOverrideReferenceStore {
    public static let targetVendorID: UInt32 = 0x4C2D
    public static let targetProductID: UInt32 = 0x76AB
    public static let targetSerialNumber: UInt32 = 0x30413332
    public static let targetLogicalWidth: Int = 2560
    public static let targetLogicalHeight: Int = 1440
    public static let targetBackingWidth: Int = 5120
    public static let targetBackingHeight: Int = 2880
    public static let targetRefreshRate: Double = 100.0

    public static let perfectQHDNormalHex = "0000140000000B40"
    public static let perfectQHDHiDPIHex = "0000140000000B400000000900A00000"

    private static let bundledReferenceFileName = "Samsung_4C2D_76AB_reference"
    private static let bundledReferenceFileExtension = "plist"

    public static var bundledReferenceURL: URL? {
        // Packaged macOS apps must keep resources under Contents/Resources.
        // Prefer Bundle.main so release builds do not need a SwiftPM bundle
        // beside Contents at the .app root, which invalidates code signing.
        let mainCandidates: [URL?] = [
            Bundle.main.url(
                forResource: bundledReferenceFileName,
                withExtension: bundledReferenceFileExtension,
                subdirectory: "HiDPIOverrides"
            ),
            Bundle.main.url(
                forResource: bundledReferenceFileName,
                withExtension: bundledReferenceFileExtension
            )
        ]
        if let packagedURL = mainCandidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            return packagedURL
        }

        #if SWIFT_PACKAGE
        // SwiftPM test/debug builds resolve the generated resource bundle.
        let packageBundle = Bundle.module
        let packageCandidates: [URL?] = [
            packageBundle.url(forResource: bundledReferenceFileName, withExtension: bundledReferenceFileExtension, subdirectory: "HiDPIOverrides"),
            packageBundle.url(forResource: bundledReferenceFileName, withExtension: bundledReferenceFileExtension),
            packageBundle.resourceURL?.appendingPathComponent("HiDPIOverrides/\(bundledReferenceFileName).\(bundledReferenceFileExtension)"),
            packageBundle.resourceURL?.appendingPathComponent("\(bundledReferenceFileName).\(bundledReferenceFileExtension)")
        ]
        return packageCandidates.compactMap { $0 }.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        })
        #else
        return nil
        #endif
    }

    public static var applicationSupportBackupURL: URL? {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let vendorHex = String(format: "%04x", targetVendorID)
        let productHex = String(format: "%04x", targetProductID)
        return baseURL
            .appendingPathComponent("AmbientSync", isDirectory: true)
            .appendingPathComponent("HiDPIOverrides", isDirectory: true)
            .appendingPathComponent("DisplayVendorID-\(vendorHex)", isDirectory: true)
            .appendingPathComponent("DisplayProductID-\(productHex)", isDirectory: false)
    }

    public static var systemOverrideURL: URL {
        let vendorHex = String(format: "%04x", targetVendorID)
        let productHex = String(format: "%04x", targetProductID)
        return URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(vendorHex)/DisplayProductID-\(productHex)")
    }

    public static var bundledReferenceExists: Bool {
        bundledReferenceURL != nil
    }

    public static var systemOverrideExists: Bool {
        FileManager.default.fileExists(atPath: systemOverrideURL.path)
    }

    public static var applicationSupportBackupExists: Bool {
        guard let url = applicationSupportBackupURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func bundledReferenceRecord() throws -> HiDPIOverridePlistRecord {
        guard let url = bundledReferenceURL else {
            throw HiDPIOverrideReferenceStoreError.bundledReferenceMissing
        }
        return try loadRecord(at: url)
    }

    public static func systemOverrideRecord() throws -> HiDPIOverridePlistRecord {
        try loadRecord(at: systemOverrideURL)
    }

    public static func applicationSupportBackupRecord() throws -> HiDPIOverridePlistRecord {
        guard let url = applicationSupportBackupURL else {
            throw HiDPIOverrideReferenceStoreError.bundledReferenceMissing
        }
        return try loadRecord(at: url)
    }

    public static func referenceSHA256() throws -> String {
        try bundledReferenceRecord().sha256
    }

    public static func systemSHA256() throws -> String {
        try systemOverrideRecord().sha256
    }

    public static func applicationSupportBackupSHA256() throws -> String {
        try applicationSupportBackupRecord().sha256
    }

    public static func systemMatchesBundledReference() -> Bool {
        guard let systemRecord = try? systemOverrideRecord(),
              let referenceRecord = try? bundledReferenceRecord() else {
            return false
        }

        return systemRecord.sha256 == referenceRecord.sha256
    }

    public static func applicationSupportBackupMatchesBundledReference() -> Bool {
        guard let backupRecord = try? applicationSupportBackupRecord(),
              let referenceRecord = try? bundledReferenceRecord() else {
            return false
        }

        return backupRecord.sha256 == referenceRecord.sha256
    }

    public static func perfectQHDRecordsPresent(in record: HiDPIOverridePlistRecord) -> Bool {
        record.perfectQHDRecordsPresent
    }

    public static func scaleResolutionCount(in record: HiDPIOverridePlistRecord) -> Int {
        record.scaleResolutions.count
    }

    public static func exportBundledReference(to destinationURL: URL) throws {
        let data = try bundledReferenceRecord().data
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: [.atomic])
    }

    public static func loadRecord(at url: URL) throws -> HiDPIOverridePlistRecord {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            var format = PropertyListSerialization.PropertyListFormat.xml
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            guard let dictionary = plist as? [String: Any] else {
                throw HiDPIOverrideReferenceStoreError.invalidPropertyList(url)
            }
            return HiDPIOverridePlistRecord(url: url, data: data, dictionary: dictionary)
        } catch let error as HiDPIOverrideReferenceStoreError {
            throw error
        } catch {
            throw HiDPIOverrideReferenceStoreError.fileUnreadable(url, underlying: error)
        }
    }

    public static func sha256(data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    static func uint32Value(_ value: Any?) -> UInt32? {
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        if let intValue = value as? Int, intValue >= 0 {
            return UInt32(intValue)
        }
        if let uintValue = value as? UInt32 {
            return uintValue
        }
        return nil
    }
}
