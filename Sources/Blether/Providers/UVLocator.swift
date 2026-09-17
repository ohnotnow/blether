import Foundation

/// Finds the `uv` binary. A menubar app launched by Finder has almost no PATH, so look where installers put it.
enum UVLocator {
    /// ~/.local/bin (uv's own installer), Homebrew, /usr/local/bin, then whatever PATH this process has.
    static var defaultCandidates: [URL] {
        var urls = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv"),
            URL(filePath: "/opt/homebrew/bin/uv"),
            URL(filePath: "/usr/local/bin/uv"),
        ]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        urls += path.split(separator: ":").filter { !$0.isEmpty }.map { URL(filePath: String($0)).appendingPathComponent("uv") }
        return urls
    }

    /// The first executable file among a non-empty override and then the candidates, in order. Nil when none.
    static func find(override: String?, candidates: [URL] = defaultCandidates) -> URL? {
        var urls = candidates
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty {
            urls.insert(URL(filePath: (override as NSString).expandingTildeInPath), at: 0)
        }
        return urls.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
