import Foundation

/// ElevenLabs over its REST API. Voice ids are the service's opaque strings; the list comes from
/// the account. Endpoint facts verified 2026-09-18 (ant blether-mYBCN).
struct ElevenLabsProvider: Provider {
    let name = "elevenlabs"
    /// Billed per character, so the old cap stays.
    let maxMainCharacters = 800
    static let modelID = "eleven_v3"
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

    /// `language` is ignored: eleven_v3 is multilingual and detects it from the text.
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

    /// Ported from claude-speaks' prompts/elevenlabs/summary.md: the tag list and the sparing rule.
    static let hint = """
    The one exception to the no-markup rule: you may drop in one or two ElevenLabs audio tags where they meaningfully aid delivery, a weary moment with [sigh], an aside with [whispers], a wry beat with [laughs] or [deadpan]. Do not over-tag. Tags you MAY use, and ONLY these: emotional states [excited], [nervous], [frustrated], [sorrowful], [calm], [tired]; reactions [sigh], [laughs], [gasps], [gulps], [whispers]; tone cues [cheerfully], [flatly], [deadpan], [playfully], [resigned tone]; cognitive beats [pauses], [hesitates], [stammers]; pacing and emphasis, even more sparingly, [drawn out], [rushed], [deliberate], [emphasized]. Tags are inline, [tag] not <tag>, placed immediately before the span they colour. Most text stays untagged; you almost never need more than two in one reply. Punctuation changes pacing too: ellipses for trailing off, and reach for a tag only when punctuation alone will not carry the beat.
    """
}
