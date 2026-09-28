import Foundation

/// ElevenLabs over its REST API. Voice ids are the service's opaque strings; the list comes from
/// the account. Endpoint facts verified 2026-09-18 (ant blether-mYBCN).
struct ElevenLabsProvider: Provider {
    let name = "elevenlabs"
    /// Billed per character, so the old cap stays.
    let maxMainCharacters = 800
    static let modelID = "eleven_v4"
    static let outputFormat = "mp3_44100_128"
    /// Read at call time so a key saved in Settings is used on the next reply without a relaunch.
    let apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    var markupHint: String? { Self.hint }

    func voices() async throws -> [Voice] {
        let data = try await SpeechHTTP.get(URL(string: "https://api.elevenlabs.io/v2/voices")!, auth: try auth(), session: session)
        let list = try JSONDecoder().decode(VoiceList.self, from: data)
        if list.hasMore == true { Log.log("elevenlabs: more voices than one page, only the first page is listed") }
        return list.voices.map { Voice(id: $0.voiceID, name: $0.name, language: $0.labels?["language"] ?? $0.labels?["accent"] ?? "unknown") }
    }

    /// `language` is ignored: eleven_v4 is multilingual and detects it from the text.
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=\(Self.outputFormat)")!
        let data = try await SpeechHTTP.post(url, auth: try auth(), json: Request(text: text, modelID: Self.modelID), session: session)
        Log.log("elevenlabs synth voice=\(voice) chars=\(text.count) bytes=\(data.count)")
        return try SpeechHTTP.clip(from: data, extension: "mp3")
    }

    private func auth() throws -> SpeechHTTP.Auth {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("elevenlabs: no API key, add one in Settings > Providers")
        }
        return .header(name: "xi-api-key", value: key)
    }

    private struct Request: Encodable {
        let text: String
        let modelID: String
        enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
        }
    }

    private struct VoiceList: Decodable {
        let voices: [Entry]
        let hasMore: Bool?
        struct Entry: Decodable {
            let voiceID: String
            let name: String
            let labels: [String: String]?
            enum CodingKeys: String, CodingKey {
                case voiceID = "voice_id"
                case name, labels
            }
        }
        enum CodingKeys: String, CodingKey {
            case voices
            case hasMore = "has_more"
        }
    }

    /// eleven_v4 has no fixed tag list, so these are examples, not a whitelist. The voice-only rule
    /// and emphasis by capitals and punctuation come from ElevenLabs' own Enhance prompt.
    static let hint = """
    DO add up to three ElevenLabs audio tags where they bring the delivery to life: a weary moment with [sighs], an aside with [whispers], a wry beat with [chuckles] or [deadpan]. There is no fixed list: any short word or phrase describing how the voice sounds works, such as [thoughtful], [annoyed], [surprised], [laughing], [clears throat], [exhales sharply] or [short pause]. Tags describe the voice only, never actions ([grinning], [pacing]), music or sound effects. Tags are inline, [tag] not <tag>, placed immediately before or after the words they colour. Never more than three in one reply. Punctuation and capitals carry delivery too: ellipses for trailing off, a CAPITALISED word for stress, an exclamation mark for energy.
    """
}
