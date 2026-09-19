/// Wraps the real client and reports the first answer that comes back, so the app can stop pointing
/// at the LLM page (the sidebar badge and the menubar line, 2026-09-19). Failures pass straight through.
struct FirstAnswerLLM: LLM {
    let wrapped: any LLM
    let onAnswer: @Sendable () -> Void

    func complete(system: String, user: String) async throws -> String {
        let answer = try await wrapped.complete(system: system, user: user)
        onAnswer()
        return answer
    }
}
