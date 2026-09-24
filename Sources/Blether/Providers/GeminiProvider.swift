import Foundation

/// Google's Gemini 3.8 Flash TTS, reached through OpenRouter's OpenAI-shaped speech endpoint, so
/// the key is an OpenRouter key. The voices are a fixed list; a tone becomes the same
/// `instructions` sentence OpenAI gets. Endpoint facts verified 2026-09-24 (ant blether-4Fcs3).
struct GeminiProvider: Provider {
    let name = "gemini"
    let keychainAccount = "openrouter"
    /// Price per character unknown on 2026-09-24, so OpenAI's cap until it is.
    let maxMainCharacters = 800
    static let model = "google/gemini-3.8-flash-tts"
    /// OpenRouter's list as documented on 2026-09-24, in that order.
    static let voiceIDs = [
        "Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Leda", "Orus", "Aoede", "Callirrhoe", "Autonoe",
        "Enceladus", "Iapetus", "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi", "Laomedeia", "Achernar",
        "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird", "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat",
    ]
    /// What comes back: headerless PCM, 24 kHz mono per the Content-Type. 16-bit is inferred from
    /// listening, not documented.
    static let sampleRate: UInt32 = 24000
    /// Read at call time so a key saved in Settings is used on the next reply without a relaunch.
    let apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func voices() async throws -> [Voice] {
        Self.voiceIDs.map { Voice(id: $0, name: $0, language: "en") }
    }

    /// `language` is ignored. Only English was tried on 2026-09-24; other languages are untested.
    func synthesise(_ text: String, voice: String, language: String?, tone: Tone?) async throws -> AudioClip {
        let url = URL(string: "https://openrouter.ai/api/v1/audio/speech")!
        // mp3 is refused for this model with a 400, whatever OpenRouter's doc says.
        let request = OpenAIProvider.Request(model: Self.model, voice: voice, input: text, responseFormat: "pcm", instructions: tone.map { OpenAIProvider.instructions[$0]! })
        let pcm = try await SpeechHTTP.post(url, auth: try auth(), json: request, session: session)
        Log.log("gemini synth voice=\(voice) tone=\(tone?.rawValue ?? "none") chars=\(text.count) bytes=\(pcm.count)")
        guard !pcm.isEmpty else { throw ProviderError.noAudio }
        return try SpeechHTTP.clip(from: Self.wav(pcm), extension: "wav")
    }

    private func auth() throws -> SpeechHTTP.Auth {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("gemini: no API key, add your OpenRouter key in Settings > Providers")
        }
        return .bearer(key)
    }

    /// A 44-byte RIFF header for 16-bit mono at `sampleRate`, then the samples.
    static func wav(_ pcm: Data) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var data = Data("RIFF".utf8)
        data += le(UInt32(36 + pcm.count))
        data += Data("WAVEfmt ".utf8)
        data += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1))
        data += le(sampleRate) + le(sampleRate * 2) + le(UInt16(2)) + le(UInt16(16))
        data += Data("data".utf8)
        data += le(UInt32(pcm.count))
        return data + pcm
    }
}
