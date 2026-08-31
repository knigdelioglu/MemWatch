import Foundation

public struct PlistDiffResult {
    public let areEqual: Bool
    public let diffDetails: String
}

public final class HiDPIOverridePlistBuilder {
    public static func exportBundledReference(to destinationURL: URL) throws {
        try HiDPIOverrideReferenceStore.exportBundledReference(to: destinationURL)
    }

    public static func compareSystemOverrideWithBundledReference() -> PlistDiffResult {
        guard HiDPIOverrideReferenceStore.systemOverrideExists else {
            return PlistDiffResult(areEqual: false, diffDetails: "Sistemde kurulu override dosyası yok.")
        }

        guard HiDPIOverrideReferenceStore.bundledReferenceExists else {
            return PlistDiffResult(areEqual: false, diffDetails: "Bundled reference plist bulunamadı.")
        }

        guard let system = try? HiDPIOverrideReferenceStore.systemOverrideRecord(),
              let reference = try? HiDPIOverrideReferenceStore.bundledReferenceRecord() else {
            return PlistDiffResult(areEqual: false, diffDetails: "Plist karşılaştırması için dosyalardan biri okunamadı.")
        }

        if system.data == reference.data {
            return PlistDiffResult(areEqual: true, diffDetails: "Kurulu olan dosya ile reference dosyası birebir eşleşmektedir.")
        }

        return PlistDiffResult(areEqual: false, diffDetails: "Kurulu olan dosya ile reference dosyası arasında byte-level farklılık bulunmaktadır.")
    }
}
