import Foundation

/// OpenAI-compatible chat completions. Covers Ollama, LM Studio, OpenRouter and OpenAI itself.
struct ChatCompletionsClient: LLM {
    /// Deliberately huge: reasoning models spend the budget on hidden thinking and return
    /// nothing if it runs out. Spoken length is capped downstream by the planner.
    static let maxTokens = 16000
    /// A cold local model took 25 s on 2026-09-17.
    static let timeout: TimeInterval = 90

    let baseURL: String
    let model: String
    let apiKey: String?
    /// JSON object text merged into the request body. Its fields win over ours, except
    /// `model` and `messages`. Invalid JSON is logged and ignored.
    var extraBody: String = "{}"
    /// The name the token budget goes under. OpenAI's newer models reject `max_tokens` (2026-09-26).
    var maxTokensField = "max_tokens"
    var session: URLSession = .shared

    func complete(system: String, user: String) async throws -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmedBase + "/chat/completions"), url.host != nil else {
            throw LLMError.badURL(baseURL)
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try body(system: system, user: user)

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        let usage = decoded?.usage.map { " tokens prompt=\($0.promptTokens ?? 0) completion=\($0.completionTokens ?? 0)" } ?? ""
        Log.log("llm \(model) status=\(status) \(elapsed)ms\(usage)")

        guard (200 ..< 300).contains(status) else {
            throw LLMError.http(status, decoded?.error?.message)
        }
        let content = decoded?.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw LLMError.emptyResponse }
        return content
    }

    private func body(system: String, user: String) throws -> Data {
        let base = try JSONEncoder().encode(Request(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)]
        ))
        guard var merged = try JSONSerialization.jsonObject(with: base) as? [String: Any] else { return base }
        merged[maxTokensField] = Self.maxTokens
        if let extra = ExtraBody.parse(extraBody) {
            for (key, value) in extra where key != "model" && key != "messages" { merged[key] = value }
        } else {
            Log.log("llm extra body ignored: not a JSON object")
        }
        return try JSONSerialization.data(withJSONObject: merged)
    }

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        let stream = false

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    /// Only the fields we read. A `reasoning` field, if present, is ignored on purpose.
    private struct Response: Decodable {
        let choices: [Choice]?
        let error: APIError?
        let usage: Usage?

        struct Choice: Decodable { let message: Message? }
        struct Message: Decodable { let content: String? }
        struct APIError: Decodable { let message: String? }
        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }
    }
}
