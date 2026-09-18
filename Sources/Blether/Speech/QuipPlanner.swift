import Foundation

struct PlannedQuip: Equatable, Sendable {
    let text: String
    /// The language name as it was picked from the list, as the user typed it; the provider maps it.
    let language: String
}

/// Turns a persona, the language list and the recent history into one short line for the
/// notification role. The counterpart of ReplyPlanner; reproduces plan_notification_clip from
/// claude-speaks' providers/openai.py.
struct QuipPlanner: Sendable {
    static let cap = 200

    let llm: any LLM

    /// nil when the model threw or returned nothing usable; the caller beeps. A nil persona quips
    /// as a plain coding assistant, so a profile whose persona was deleted is still heard.
    func plan(persona: Persona?, languages: NotificationLanguages, history: [String]) async -> PlannedQuip? {
        let language = languages.pick()
        Log.log("notification language: \(language)")
        let voice = persona?.description ?? "a coding assistant"
        do {
            let raw = try await llm.complete(system: Prompts.notification(persona: voice, language: language, history: history), user: "")
            var line = SpeechText.firstLine(raw)
            if line != raw.trimmingCharacters(in: .whitespacesAndNewlines) {
                Log.log("notification guard: multi-line output, kept first line")
            }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                Log.log("notification: model returned empty content")
                return nil
            }
            Log.log("notification: \(line)")
            return PlannedQuip(text: SpeechText.cap(line, limit: Self.cap), language: language)
        } catch {
            Log.log("notification error: \(error)")
            return nil
        }
    }
}
