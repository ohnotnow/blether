import Foundation
import Synchronization

/// Mistral's speech endpoint. Presets are one speaker at one mood, named by slug ("en_paul_sad"), and
/// the speech endpoint accepts a slug as the voice id (checked live 2026-09-18). A tone swaps the
/// chosen preset for the same speaker's sibling in that mood, when there is one; a speaker with no
/// such sibling, or a custom (UUID) voice, is left alone. Endpoint facts: ant blether-mYBCN.
final class MistralProvider: Provider, Sendable {
    let name = "mistral"
    /// Billed per character, so the old cap stays.
    let maxMainCharacters = 800
    static let model = "voxtral-mini-tts-2603"
    /// Read at call time so a key saved in Settings is used on the next reply without a relaunch.
    let apiKey: @Sendable () -> String?
    let session: URLSession

    /// Preset slugs by speaker prefix ("en_paul": ["sad", "neutral", ...]), filled by the voice list.
    private let moods = Mutex<[String: Set<String>]?>(nil)

    init(apiKey: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Our nine tones as Mistral's mood words. nil means no sibling is ever looked for.
    static func mood(for tone: Tone) -> String? {
        switch tone {
        case .neutral: "neutral"
        case .sarcasm: "sarcasm"
        case .shameful, .sad: "sad"
        case .frustrated: "frustrated"
        case .confident: "confident"
        case .confused, .curious, .jealousy: nil
        }
    }

    /// The sibling preset for the tone, or the voice unchanged. `moods` is speaker to mood words.
    static func voiceID(_ voice: String, tone: Tone?, moods: [String: Set<String>]) -> String {
        guard let tone, let wanted = mood(for: tone), let cut = voice.lastIndex(of: "_") else { return voice }
        let speaker = String(voice[..<cut])
        guard let available = moods[speaker], available.contains(wanted) else { return voice }
        return speaker + "_" + wanted
    }

    func voices() async throws -> [Voice] {
        let list = try await fetchVoices()
        return list.map { Voice(id: $0.slug ?? $0.id, name: $0.name ?? $0.slug ?? $0.id, language: $0.languages?.first ?? "unknown") }
    }

    /// `language` is ignored: the service detects it from the text.
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        let resolved = Self.voiceID(voice, tone: tone, moods: try await moodTable(needed: tone != nil))
        if resolved != voice { Log.log("mistral: \(voice) in \(tone?.rawValue ?? "") is \(resolved)") }
        let url = URL(string: "https://api.mistral.ai/v1/audio/speech")!
        let data = try await SpeechHTTP.post(url, auth: try auth(), json: Request(input: text, model: Self.model, voiceID: resolved, responseFormat: "mp3"), session: session)
        guard let reply = try? JSONDecoder().decode(Response.self, from: data), let encoded = reply.audioData, let audio = Data(base64Encoded: encoded) else {
            throw ProviderError.noAudio
        }
        Log.log("mistral synth voice=\(resolved) chars=\(text.count) bytes=\(audio.count)")
        return try SpeechHTTP.clip(from: audio, extension: "mp3")
    }

    /// The speaker-to-moods table, fetched once (a free GET) the first time a tone needs it.
    /// A fetch failure is logged and the voice is spoken as chosen rather than the reply failing.
    private func moodTable(needed: Bool) async throws -> [String: Set<String>] {
        guard needed else { return [:] }
        if let cached = moods.withLock({ $0 }) { return cached }
        do {
            _ = try await fetchVoices()
        } catch {
            Log.log("mistral: could not list voices for tone, speaking as chosen: \(error)")
        }
        return moods.withLock { $0 } ?? [:]
    }

    private func fetchVoices() async throws -> [VoiceList.Entry] {
        let data = try await SpeechHTTP.get(URL(string: "https://api.mistral.ai/v1/audio/voices")!, auth: try auth(), session: session)
        let list = try JSONDecoder().decode(VoiceList.self, from: data)
        var table: [String: Set<String>] = [:]
        for entry in list.items {
            guard let slug = entry.slug, let cut = slug.lastIndex(of: "_") else { continue }
            table[String(slug[..<cut]), default: []].insert(String(slug[slug.index(after: cut)...]))
        }
        moods.withLock { $0 = table }
        return list.items
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
            let slug: String?
            let name: String?
            let languages: [String]?
        }
    }
}
