import Foundation

@main
struct CleanupScannerBehaviorTests {
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MemWatchScannerBehavior-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let requested = home.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: requested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let payload = Data(repeating: 0x5A, count: 1_100_000)
        let first = requested.appendingPathComponent("first.bin")
        let hardlink = requested.appendingPathComponent("first-hardlink.bin")
        let physicalCopy = requested.appendingPathComponent("second.bin")
        try payload.write(to: first)
        try fm.linkItem(at: first, to: hardlink)
        try payload.write(to: physicalCopy)

        let context = CleanupScanContext(
            homeDirectory: home,
            requestedRoots: [requested],
            projectRoots: [],
            now: Date()
        )
        let duplicateItems = try await ExactDuplicateScanner().scan(context: context)
        precondition(duplicateItems.count == 1, "One hardlink plus one physical copy should produce exactly one reclaimable duplicate")
        precondition(duplicateItems[0].safety == .review)
        precondition(duplicateItems[0].deletionMode == .trash)

        let models = home.appendingPathComponent(".ollama/models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 4096).write(to: models.appendingPathComponent("weights.gguf"))
        let aiItems = try await AIArtifactScanner().scan(context: context)
        guard let ollama = aiItems.first(where: { $0.displayName == "Ollama models" }) else {
            preconditionFailure("Ollama model root should be detected")
        }
        precondition(ollama.ruleID.rawValue == "ai.model")
        precondition(ollama.safety == .protected, "Downloaded model weights must remain Protected")
        precondition(ollama.deletionMode == .none, "Downloaded model weights must not get a deletion mode")

        print("PASS Cleanup scanner hardlink and AI safeguards")
    }
}
