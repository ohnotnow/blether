import Foundation

/// Decides the mood of a reply. One label, one place; providers express it or ignore it.
protocol ToneClassifier: Sendable {
    /// Throws on any failure; the caller falls back to neutral and says nothing about it.
    func classify(_ text: String) async throws -> Tone
}

enum ToneError: Error, Equatable {
    case noStyle
    case unknownStyle(String)
}

/// The old claude-speaks classifier prompt through the one global LLM.
struct LLMToneClassifier: ToneClassifier {
    let llm: any LLM

    func classify(_ text: String) async throws -> Tone {
        let raw = try await llm.complete(system: Prompts.toneClassifier, user: text)
        return try Self.parse(raw)
    }

    /// The first {...} block in the reply, in case the model chats around its JSON.
    static func parse(_ raw: String) throws -> Tone {
        guard let open = raw.firstIndex(of: "{"), let close = raw[open...].firstIndex(of: "}") else { throw ToneError.noStyle }
        let json = try? JSONSerialization.jsonObject(with: Data(raw[open...close].utf8)) as? [String: Any]
        guard let style = json?["style"] as? String else { throw ToneError.noStyle }
        guard let tone = Tone(rawValue: style.lowercased()) else { throw ToneError.unknownStyle(style) }
        return tone
    }
}

/// Jev, Typesafe's classification model: one choice question whose criteria are the nine tones.
/// Request and response shapes are in jev.md at the repo root.
struct JevToneClassifier: ToneClassifier {
    static let url = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let model = "jev-latest"
    static let instructions = "How should this coding assistant's reply sound when spoken aloud? Most replies are neutral; pick another only when the tone is unmistakable."
    /// Read at call time, off the main actor, like the providers' keys.
    let apiKey: @Sendable () -> String?
    var session: URLSession = .shared

    func classify(_ text: String) async throws -> Tone {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderError.other("jev: no API key, add one in Settings > Tone")
        }
        let question = Request.Question(criteria: Dictionary(uniqueKeysWithValues: Tone.allCases.map { ($0.rawValue, $0.criterion) }))
        let data = try await SpeechHTTP.post(Self.url, auth: .bearer(key), json: Request(state: text, questions: ["tone": question]), session: session)
        let reply = try JSONDecoder().decode(Response.self, from: data)
        guard let choice = reply.answers?.tone?.choice else { throw ToneError.noStyle }
        guard let tone = Tone(rawValue: choice) else { throw ToneError.unknownStyle(choice) }
        let confidence = reply.answers?.tone?.confidence.map { String(format: "%.2f", $0) } ?? "?"
        Log.log("tone: \(tone.rawValue) (\(confidence))")
        return tone
    }

    private struct Request: Encodable {
        let state: String
        let model = JevToneClassifier.model
        let questions: [String: Question]
        struct Question: Encodable {
            let type = "choice"
            let instructions = JevToneClassifier.instructions
            let criteria: [String: String]
        }
    }

    private struct Response: Decodable {
        let answers: Answers?
        struct Answers: Decodable { let tone: Answer? }
        struct Answer: Decodable {
            let choice: String?
            let confidence: Double?
        }
    }
}
