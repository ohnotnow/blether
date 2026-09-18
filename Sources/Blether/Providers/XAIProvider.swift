import Foundation

/// xAI's speech endpoint. The language is always "auto" (the service detects it). Endpoint facts
/// verified 2026-09-18 (ant blether-mYBCN); the voice-list response shape was not documented, so
/// it is decoded leniently and falls back to the three ids the docs named.
struct XAIProvider: Provider {
    let name = "xai"
    /// Billed per character, so the old cap stays.
    let maxMainCharacters = 800
    static let knownVoiceIDs = ["eve", "ara", "rex"]
    /// Read at call time so a key saved in Settings is used on the next reply without a relaunch.
    let apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    var markupHint: String? { Self.hint }

    func voices() async throws -> [Voice] {
        let data = try await SpeechHTTP.get(URL(string: "https://api.x.ai/v1/tts/voices")!, auth: try auth(), session: session)
        if let voices = Self.parseVoices(data), !voices.isEmpty { return voices }
        Log.log("xai: unrecognised voice list shape, using the known ids: \(Log.preview(String(decoding: data.prefix(200), as: UTF8.self)))")
        return Self.knownVoiceIDs.map { Voice(id: $0, name: $0.capitalized, language: "en") }
    }

    /// An array of objects with "voice_id" or "id" and "name", either at the top level or under "voices".
    static func parseVoices(_ data: Data) -> [Voice]? {
        let json = try? JSONSerialization.jsonObject(with: data)
        let entries = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["voices"] as? [[String: Any]])
        guard let entries else { return nil }
        let voices = entries.compactMap { entry -> Voice? in
            guard let id = (entry["voice_id"] ?? entry["id"]) as? String else { return nil }
            return Voice(id: id, name: entry["name"] as? String ?? id.capitalized, language: entry["language"] as? String ?? "unknown")
        }
        return voices.isEmpty ? nil : voices
    }

    /// `language` is ignored: "auto" is sent whatever the argument.
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        let url = URL(string: "https://api.x.ai/v1/tts")!
        let data = try await SpeechHTTP.post(url, auth: try auth(), json: Request(text: text, voiceID: voice), session: session)
        Log.log("xai synth voice=\(voice) chars=\(text.count) bytes=\(data.count)")
        return try SpeechHTTP.clip(from: data, extension: "mp3")
    }

    private func auth() throws -> SpeechHTTP.Auth {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("xai: no API key, add one in Settings > Providers")
        }
        return .bearer(key)
    }

    private struct Request: Encodable {
        let text: String
        let voiceID: String
        let language = "auto"
        let outputFormat = OutputFormat()
        struct OutputFormat: Encodable {
            let codec = "mp3"
            let sampleRate = 24000
            let bitRate = 64000
            enum CodingKeys: String, CodingKey {
                case codec
                case sampleRate = "sample_rate"
                case bitRate = "bit_rate"
            }
        }
        enum CodingKeys: String, CodingKey {
            case text, language
            case voiceID = "voice_id"
            case outputFormat = "output_format"
        }
    }

    /// Ported from claude-speaks' prompts/xai/summary.md: the tag list and the sparing rule.
    static let hint = """
    The one exception to the no-markup rule: you may wrap one or two spans in xAI prosody tags where they meaningfully aid delivery, an aside in <soft>, a key conclusion in <emphasis>, a weary moment in <slow>. Do not over-tag. Tags you MAY use, and ONLY these: <soft>quieter, intimate</soft>, <whisper>conspiratorial</whisper>, <loud>raised voice</loud>, <emphasis>the important word</emphasis>, <slow>weighty, deliberate</slow>, <fast>urgent, rushed</fast>, <higher-pitch>questioning, surprised</higher-pitch>, <lower-pitch>grave, serious</lower-pitch>, <build-intensity>escalating</build-intensity>, <decrease-intensity>winding down</decrease-intensity>, <laugh-speak>amused while talking</laugh-speak>, <sing-song>playful</sing-song>. Most text stays untagged; wrap one or two spans, no more. Tags must be balanced, open and close.
    """
}
