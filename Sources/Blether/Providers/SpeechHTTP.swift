import Foundation

/// The one HTTP shape every API provider uses: a JSON POST or a GET with a key header, a status
/// check, and the body back as Data. Providers decide the URL, the header, the body and what the
/// response means. Nothing here logs a header.
enum SpeechHTTP {
    static let timeout: TimeInterval = 30

    enum Auth {
        case bearer(String)
        case header(name: String, value: String)
    }

    /// Throws ProviderError.http(status) on a non-2xx reply, logging the start of the body (the
    /// services put their error message there), and .other on a transport failure.
    static func post(_ url: URL, auth: Auth, json body: some Encodable, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, auth: auth, session: session)
    }

    /// Same for a GET, used for voice lists.
    static func get(_ url: URL, auth: Auth, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        return try await send(request, auth: auth, session: session)
    }

    /// Audio bytes to a fresh temp file the playback queue will delete. Empty data throws .noAudio.
    static func clip(from data: Data, extension ext: String) throws -> AudioClip {
        guard !data.isEmpty else { throw ProviderError.noAudio }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return AudioClip(url: url)
    }

    /// One log line per call, in the style of the LLM client's, plus milliseconds. Never the key.
    private static func send(_ request: URLRequest, auth: Auth, session: URLSession) async throws -> Data {
        var request = request
        switch auth {
        case .bearer(let key): request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .header(let name, let value): request.setValue(value, forHTTPHeaderField: name)
        }
        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.other(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Log.log("http \(request.httpMethod ?? "") \(request.url?.host() ?? "")\(request.url?.path() ?? "") status=\(status) \(elapsed)ms bytes=\(data.count)")
        guard (200 ..< 300).contains(status) else {
            Log.log("http error body: \(Log.preview(String(decoding: data.prefix(200), as: UTF8.self)))")
            throw ProviderError.http(status)
        }
        return data
    }
}
