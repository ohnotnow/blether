import Foundation

enum StreamPlaylistError: Error, CustomStringConvertible {
    case empty(URL)

    var description: String {
        switch self {
        case .empty(let url): "no streams listed in \(url.lastPathComponent)"
        }
    }
}

/// Turns the stream URL the user pasted into the URLs AVPlayer should try, in order. Stations hand
/// out .m3u and .pls files that point at the real stream, and a .pls often lists mirrors, which
/// become fallbacks (ant blether-pHUqx). One level only: an entry that is itself a playlist is not fetched.
enum StreamPlaylist {
    /// .m3u8 is HLS, which AVPlayer plays itself, so it is not in this list.
    private static let playlistExtensions: Set<String> = ["m3u", "pls"]

    static func isPlaylist(_ url: URL) -> Bool {
        playlistExtensions.contains(url.pathExtension.lowercased())
    }

    /// The stream URLs in a .m3u or .pls body. A body with a [playlist] header is read as .pls
    /// (FileN= lines, by N); anything else as .m3u (every line that is not blank or a # comment).
    static func entries(in body: String, base: URL) -> [URL] {
        let lines = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let raw: [String]
        if lines.contains(where: { $0.lowercased() == "[playlist]" }) {
            raw = lines.compactMap { line -> (Int, String)? in
                guard let equals = line.firstIndex(of: "=") else { return nil }
                let key = line[..<equals].lowercased()
                guard key.hasPrefix("file"), let n = Int(key.dropFirst(4)) else { return nil }
                return (n, String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces))
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        } else {
            raw = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        return raw.compactMap { URL(string: $0, relativeTo: base)?.absoluteURL }
    }

    /// Fetches `url` when it is a playlist and returns its entries; any other URL is returned as it is.
    static func resolve(_ url: URL, fetch: (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }) async throws -> [URL] {
        guard isPlaylist(url) else { return [url] }
        let body = String(decoding: try await fetch(url), as: UTF8.self)
        let urls = entries(in: body, base: url)
        guard !urls.isEmpty else { throw StreamPlaylistError.empty(url) }
        return urls
    }
}
