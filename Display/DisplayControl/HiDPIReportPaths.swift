import Foundation

public enum HiDPIReportPaths {
    public static func projectRootURL(
        fileManager: FileManager = .default
    ) -> URL {
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MemWatch/Reports", isDirectory: true)
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MemWatch/Reports", isDirectory: true)
    }

    public static func reportURL(_ relativePath: String) -> URL {
        projectRootURL().appendingPathComponent(relativePath)
    }

    public static func write(_ content: String, to relativePath: String) throws -> URL {
        let url = reportURL(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
