import Foundation

/// OpenAI's speech endpoint. The voices are a fixed list; a tone becomes one `instructions`
/// sentence. Endpoint facts verified 2026-09-18 (ant blether-mYBCN).
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
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        let request = Request(model: Self.model, voice: voice, input: text, responseFormat: "mp3", instructions: tone.map { Self.instructions[$0]! })
        let data = try await SpeechHTTP.post(url, auth: try auth(), json: request, session: session)
        Log.log("openai synth voice=\(voice) tone=\(tone?.rawValue ?? "none") chars=\(text.count) bytes=\(data.count)")
        return try SpeechHTTP.clip(from: data, extension: "mp3")
    }

    private func auth() throws -> SpeechHTTP.Auth {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("openai: no API key, add one in Settings > Providers")
        }
        return .bearer(key)
    }

    /// Delivery directions per tone, omitted from the body when there is no tone. Blunt on purpose:
    /// the model's default is relentlessly upbeat and a polite hint does not move it (heard 2026-09-18).
    static let instructions: [Tone: String] = [
        .neutral: "Flat, even and unhurried. No enthusiasm, no smile in the voice, no rising lilt at the end of sentences. A tired colleague reading notes aloud in a quiet office.",
        .sarcasm: "Bone dry and deadpan. Slow, level, faintly contemptuous, as if every word is obviously beneath you. Never sound pleased or upbeat.",
        .confused: "Genuinely lost. Halting, with pauses, rising doubtfully at the end of phrases, as if you are not sure you have understood the question.",
        .shameful: "You have made a serious mistake and you are ashamed of it. Quiet, slow, hesitant, almost mumbling, like someone admitting fault and expecting to be told off. No brightness at all.",
        .sad: "Low and heavy. Slow, with long pauses, trailing off, close to a sigh. Sound defeated and resigned. Absolutely no cheer.",
        .jealousy: "Sour and pointed. Tight, clipped, a little bitter, as if someone else got the thing you wanted.",
        .frustrated: "Fed up and irritable. Tense, clipped and fast, with a hard edge, through gritted teeth. Civil, but plainly out of patience.",
        .curious: "Quietly intrigued, thinking aloud. Measured, with small pauses, as if turning something over to look at it. Not excited, interested.",
        .confident: "Firm, calm and certain. Steady pace, no hedging, no upward inflection. Assured rather than excited: a statement, not a celebration.",
    ]

    private struct Request: Encodable {
        let model: String
        let voice: String
        let input: String
        let responseFormat: String
        let instructions: String?
        enum CodingKeys: String, CodingKey {
            case model, voice, input, instructions
            case responseFormat = "response_format"
        }
    }
}
