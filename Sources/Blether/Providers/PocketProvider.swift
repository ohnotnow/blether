import Foundation

/// Kyutai's Pocket TTS on the CPU, spoken to through its own resident helper (Helpers/pocket.py) via
/// HelperProcess. Its voices are Kyutai's catalogue, listed by the helper when it is ready.
final class PocketProvider: Provider, Sendable {
    let name = "pocket"
    /// Local and many times faster than real time, so the same allowance as Kokoro.
    let maxMainCharacters = 3000

    private let helper: HelperProcess
    private let requestTimeout: Duration

    /// `requestTimeout` covers a request that arrives during a first-run model download.
    init(executable: URL, arguments: [String], requestTimeout: Duration = .seconds(90), onState: @escaping @Sendable (HelperProcess.State) -> Void) {
        helper = HelperProcess(executable: executable, arguments: arguments, onState: onState)
        self.requestTimeout = requestTimeout
    }

    func start() async { await helper.start() }
    nonisolated func stop() { helper.stop() }

    func voices() async throws -> [Voice] {
        await helper.start()
        try Task.checkCancellation()
        if case .failed(let message) = await helper.state { throw ProviderError.other(message) }
        return await helper.voices.map { Voice(id: $0.id, name: $0.name, language: $0.language) }
    }

    /// `language` and `tone` are ignored: the English model reads every text, and tone is not expressed yet.
    func synthesise(_ text: String, voice id: String, language: String?, tone: Tone?) async throws -> AudioClip {
        await helper.start()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        do {
            try await helper.request(text: text, voice: id, out: url, timeout: requestTimeout)
        } catch let error as HelperError {
            throw Self.providerError(error)
        }
        return AudioClip(url: url)
    }

    private static func providerError(_ error: HelperError) -> ProviderError {
        switch error {
        case .timedOut: .timedOut
        case .refused(let message): .other(message)
        case .notReady: .other("Pocket is not running")
        case .exited(let code): .other("Pocket helper exited with \(code)")
        case .badReply(let line): .other(line)
        }
    }
}
