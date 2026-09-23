import Foundation

/// Breeze-TTS-2 on MLX, spoken to through its own resident helper (Helpers/breeze.py) via HelperProcess.
/// It has no voices of its own: a voice is a design from Settings, whose description goes to the helper
/// with every clip (blether-WtzbG).
final class BreezeProvider: Provider, Sendable {
    let name = "breeze"
    /// The user's decision (blether-FGSKN): Kokoro's 3000 would be minutes of generating at Better.
    let maxMainCharacters = 800

    private let helper: HelperProcess
    private let settings: @Sendable () -> (designs: [VoiceDesign], quality: BreezeQuality)
    private let requestTimeout: Duration

    /// `requestTimeout` covers a first request queued behind the 2.3 GB model download; a warm
    /// 800-character reply at Better takes a minute or two.
    init(
        executable: URL,
        arguments: [String],
        settings: @escaping @Sendable () -> (designs: [VoiceDesign], quality: BreezeQuality),
        requestTimeout: Duration = .seconds(300),
        onState: @escaping @Sendable (HelperProcess.State) -> Void
    ) {
        helper = HelperProcess(executable: executable, arguments: arguments, onState: onState)
        self.settings = settings
        self.requestTimeout = requestTimeout
    }

    func start() async { await helper.start() }
    nonisolated func stop() { helper.stop() }

    /// The designs, without starting the helper: listing voices must not load 2.3 GB.
    func voices() async throws -> [Voice] {
        settings().designs.map(\.voice)
    }

    /// `language` and `tone` are ignored: Breeze reads the text as written, and tone is not expressed yet.
    func synthesise(_ text: String, voice id: String, language: String?, tone: Tone?) async throws -> AudioClip {
        let (designs, quality) = settings()
        guard let design = designs.first(where: { $0.id == id }) ?? designs.first else {
            throw ProviderError.other("no Breeze voice designs")
        }
        if design.id != id { Log.log("breeze: no design \"\(id)\", speaking as \(design.name)") }
        await helper.start()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        do {
            try await helper.request(text: text, voice: design.id, out: url, instruct: design.description, cfg: quality.cfgScale, timeout: requestTimeout)
        } catch let error as HelperError {
            throw Self.providerError(error)
        }
        return AudioClip(url: url)
    }

    private static func providerError(_ error: HelperError) -> ProviderError {
        switch error {
        case .timedOut: .timedOut
        case .refused(let message): .other(message)
        case .notReady: .other("Breeze is not running")
        case .exited(let code): .other("Breeze helper exited with \(code)")
        case .badReply(let line): .other(line)
        }
    }
}
