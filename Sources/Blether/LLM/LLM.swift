/// The one global LLM. One system prompt, one user message, plain text back.
protocol LLM: Sendable {
    func complete(system: String, user: String) async throws -> String
}

enum LLMError: Error, Equatable {
    case badURL(String)
    /// HTTP status and the server's error message if it sent one.
    case http(Int, String?)
    case emptyResponse
    case transport(String)
}
