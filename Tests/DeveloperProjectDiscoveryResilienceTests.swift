import Foundation

@main
struct DeveloperProjectDiscoveryResilienceTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MemWatchDiscoveryStress-" + UUID().uuidString, isDirectory: true)
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        let first = projects.appendingPathComponent("first/Cargo.toml")
        let second = projects.appendingPathComponent("second/Cargo.toml")
        let restricted = projects.appendingPathComponent("restricted/nested/Cargo.toml")
        let outside = root.appendingPathComponent("outside/Cargo.toml")
        try fileManager.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: restricted.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[package]".utf8).write(to: first)
        try Data("[package]".utf8).write(to: second)
        try Data("[package]".utf8).write(to: restricted)
        try Data("[package]".utf8).write(to: outside)
        try fileManager.createSymbolicLink(
            at: projects.appendingPathComponent("linked-outside", isDirectory: true),
            withDestinationURL: outside.deletingLastPathComponent()
        )
        defer { try? fileManager.removeItem(at: root) }

        let discovery = DeveloperProjectDiscovery(isKnownInaccessible: { url in
            url.lastPathComponent == "restricted"
        })
        let result = try discovery.discoverWithDiagnostics(in: [projects])
        let paths = Set(result.manifests.map { $0.manifestURL.deletingLastPathComponent().lastPathComponent })
        precondition(paths.contains("first") && paths.contains("second"), "Accessible projects must survive an inaccessible descendant")
        precondition(!paths.contains("nested"), "The inaccessible subtree must not be traversed")
        precondition(result.issues.contains { $0.path.hasSuffix("restricted") }, "Skipped subtree must produce a diagnostic issue")
        precondition(!result.manifests.contains { $0.manifestURL.path.contains("outside") }, "Symlink traversal must remain disabled")

        let inaccessibleFile = root.appendingPathComponent("not-a-root-directory")
        try Data("not a directory".utf8).write(to: inaccessibleFile)
        do {
            _ = try discovery.discover(in: [inaccessibleFile])
            preconditionFailure("A configured non-directory root must retain fatal inaccessible-root behavior")
        } catch DeveloperProjectDiscoveryError.inaccessibleRoot {
            // Expected fatal root behavior.
        }

        print("PASS developer-project discovery subtree resilience and symlink safety")
    }
}
