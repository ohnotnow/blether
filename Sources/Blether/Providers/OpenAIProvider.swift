import Foundation

/// OpenAI's speech endpoint. The voices are a fixed list; no `instructions` field in this slice
/// (that is tone, blether-UkLWZ.12). Endpoint facts verified 2026-09-18 (ant blether-mYBCN).
struct OpenAIProvider: Provider {
    let name = "openai"
    /// Billed per character, so the old cap stays; well under the service's 4096 limit.
    let maxMainCharacters = 800
    static let model = "gpt-4o-mini-tts"
    /// The service's list as documented on 2026-09-18, in that order.
    static let voiceIDs = ["alloy", "ash", "ballad", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer", "verse", "marin", "cedar"]
    /// Read at call time so a key saved in Settings is used on the next reply without a relaunch.
    let apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func voices() async throws -> [Voice] {
        Self.voiceIDs.map { Voice(id: $0, name: $0.capitalized, language: "en") }
    }

    /// `language` is ignored: the service detects it from the text.
    func synthesise(_ text: String, voice: String, language: String?) async throws -> AudioClip {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        let data = try await SpeechHTTP.post(url, auth: try auth(), json: Request(model: Self.model, voice: voice, input: text, responseFormat: "mp3"), session: session)
        Log.log("openai synth voice=\(voice) chars=\(text.count) bytes=\(data.count)")
        return try SpeechHTTP.clip(from: data, extension: "mp3")
    }

    private func auth() throws -> SpeechHTTP.Auth {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("openai: no API key, add one in Settings > Providers")
        }
        return .bearer(key)
    }

    private struct Request: Encodable {
        let model: String
        let voice: String
        let input: String
        let responseFormat: String
        enum CodingKeys: String, CodingKey {
            case model, voice, input
            case responseFormat = "response_format"
        }
    }
}
