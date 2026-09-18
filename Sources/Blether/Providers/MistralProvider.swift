import Foundation

/// Mistral's speech endpoint. Voice ids are literal; the classifier that once chose a style suffix
/// is tone, blether-UkLWZ.12. Endpoint facts verified 2026-09-18 (ant blether-mYBCN).
struct MistralProvider: Provider {
    let name = "mistral"
    /// Billed per character, so the old cap stays.
    let maxMainCharacters = 800
    static let model = "voxtral-mini-tts-2603"
    /// Read at call time so a key saved in Settings is used on the next reply without a relaunch.
    let apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func voices() async throws -> [Voice] {
        let data = try await SpeechHTTP.get(URL(string: "https://api.mistral.ai/v1/audio/voices")!, auth: try auth(), session: session)
        let list = try JSONDecoder().decode(VoiceList.self, from: data)
        return list.items.map { Voice(id: $0.id, name: $0.name ?? $0.id, language: $0.languages?.first ?? "unknown") }
    }

    /// `language` is ignored: the service detects it from the text.
    func synthesise(_ text: String, voice: String, language: String?) async throws -> AudioClip {
        let url = URL(string: "https://api.mistral.ai/v1/audio/speech")!
        let data = try await SpeechHTTP.post(url, auth: try auth(), json: Request(input: text, model: Self.model, voiceID: voice, responseFormat: "mp3"), session: session)
        guard let reply = try? JSONDecoder().decode(Response.self, from: data), let encoded = reply.audioData, let audio = Data(base64Encoded: encoded) else {
            throw ProviderError.noAudio
        }
        Log.log("mistral synth voice=\(voice) chars=\(text.count) bytes=\(audio.count)")
        return try SpeechHTTP.clip(from: audio, extension: "mp3")
    }

    private func auth() throws -> SpeechHTTP.Auth {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("mistral: no API key, add one in Settings > Providers")
        }
        return .bearer(key)
    }

    private struct Request: Encodable {
        let input: String
        let model: String
        let voiceID: String
        let responseFormat: String
        enum CodingKeys: String, CodingKey {
            case input, model
            case voiceID = "voice_id"
            case responseFormat = "response_format"
        }
    }

    private struct Response: Decodable {
        let audioData: String?
        enum CodingKeys: String, CodingKey {
            case audioData = "audio_data"
        }
    }

    private struct VoiceList: Decodable {
        let items: [Entry]
        struct Entry: Decodable {
            let id: String
            let name: String?
            let languages: [String]?
        }
    }
}
