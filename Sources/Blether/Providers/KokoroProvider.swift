import Foundation

/// Kokoro-82M on MLX, spoken to through the resident helper (Helpers/kokoro.py) via HelperProcess.
final class KokoroProvider: Provider, Sendable {
    let name = "kokoro"
    /// Local synthesis is free, so the reply may run long; claude-speaks used the same figure.
    let maxMainCharacters = 3000
    /// Kokoro's own flagship voice. The user has no voice preference (ant, 2026-09-17); this is a plain default.
    static let defaultVoiceID = "af_heart"

    private let helper: HelperProcess
    private let requestTimeout: Duration

    /// `requestTimeout` covers a request that arrives during a first-run model download; warm requests take well under a second.
    init(executable: URL, arguments: [String], requestTimeout: Duration = .seconds(90), onState: @escaping @Sendable (HelperProcess.State) -> Void) {
        helper = HelperProcess(executable: executable, arguments: arguments, onState: onState)
        self.requestTimeout = requestTimeout
    }

    func start() async { await helper.start() }
    nonisolated func stop() { helper.stop() }

    func voices() async throws -> [Voice] {
        await helper.start()
        if case .failed(let message) = await helper.state { throw ProviderError.other(message) }
        return await helper.voices.map { Voice(id: $0.id, name: $0.name, language: $0.language) }
    }

    func synthesise(_ text: String, voice id: String, language: String?) async throws -> AudioClip {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        do {
            try await helper.request(text: text, voice: id, out: url, lang: Self.langCode(for: language), timeout: requestTimeout)
        } catch let error as HelperError {
            throw Self.providerError(error)
        }
        return AudioClip(url: url)
    }

    /// Kokoro's pronunciation model is per language of the text (blether-9X77J). Keyed on the first
    /// word of the name, lower-cased, so "Chinese (Simplified)" and "American English" both resolve.
    private static let langCodes: [String: String] = [
        "english": "b", "british": "b", "american": "a", "spanish": "e", "french": "f", "hindi": "h",
        "italian": "i", "portuguese": "p", "chinese": "z", "japanese": "j",
    ]

    /// nil means the helper's default (British English). An unknown name also gives nil, with a log
    /// line, so the quip is still heard, read as English.
    static func langCode(for language: String?) -> String? {
        guard let language else { return nil }
        let first = language.lowercased().split { !$0.isLetter }.first.map(String.init) ?? ""
        if let code = langCodes[first] { return code }
        Log.log("kokoro: no pronunciation model for \"\(language)\", reading it as English")
        return nil
    }

    private static func providerError(_ error: HelperError) -> ProviderError {
        switch error {
        case .timedOut: .timedOut
        case .refused(let message): .other(message)
        case .notReady: .other("Kokoro is not running")
        case .exited(let code): .other("Kokoro helper exited with \(code)")
        case .badReply(let line): .other(line)
        }
    }
}
