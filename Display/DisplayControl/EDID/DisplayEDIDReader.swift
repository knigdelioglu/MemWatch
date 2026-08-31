import CoreGraphics
import Foundation

@MainActor
final class DisplayEDIDReader {
    static let shared = DisplayEDIDReader()

    private let ioRegistryReader = EDIDIORegistryReader()

    private init() {}

    func readEDID(for displayID: CGDirectDisplayID) -> EDIDDiagnosticSummary {
        ioRegistryReader.readDiagnosticSummary(for: displayID)
    }

    func writeDiagnosticReport(summary: EDIDDiagnosticSummary) -> URL? {
        try? EDIDDiagnosticReporter.writeMarkdownReport(summary: summary)
    }
}
