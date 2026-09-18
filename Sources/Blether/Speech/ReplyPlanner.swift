import Foundation

struct PlannedClip: Equatable, Sendable {
    let text: String
    let role: Role
    /// The reply's mood, on the main clip only, when a classifier ran and succeeded.
    var tone: Tone? = nil
}

/// Turns a stripped reply into ordered clips: an optional in-character preamble, then the
/// reply itself or a compressed version of it. Reproduces plan_stop_clips, marvinise and
/// reformat_text from claude-speaks' providers/openai.py, once, for every provider.
struct ReplyPlanner: Sendable {
    static let summaryWordThreshold = 60
    static let preambleCap = 200

    let llm: any LLM

    /// `text` is already markdown-stripped and non-empty. With `includeMain` false the summariser is
    /// never called and only the preamble (if any) comes back; a preamble failure is then log only.
    /// `mainCap` is the provider's `maxMainCharacters` and `markupHint` its `markupHint`. A `classifier`
    /// runs alongside the summary and colours the main clip; its failure is log only.
    func plan(_ text: String, monologuePersona: Persona?, mainPersona: Persona?, includePreamble: Bool, includeMain: Bool, mainCap: Int, markupHint: String? = nil, classifier: (any ToneClassifier)? = nil) async -> [PlannedClip] {
        async let preambleResult = preamble(for: text, persona: includePreamble ? monologuePersona : nil)
        async let toneResult = tone(of: text, classifier: includeMain ? classifier : nil)
        let summary: Result<String, RoleFailure>? = includeMain ? await self.summary(of: text, persona: mainPersona, markupHint: markupHint) : nil
        let preamble = await preambleResult
        let tone = await toneResult

        var clips: [PlannedClip] = []
        if case .success(let line?) = preamble {
            clips.append(PlannedClip(text: SpeechText.cap(line + " ...", limit: Self.preambleCap), role: .monologue))
        }
        guard let summary else { return clips }

        var main = (try? summary.get()) ?? text
        let failed = [preamble.failedName, summary.failedName].compactMap { $0 }
        if !failed.isEmpty {
            main = "Heads up, the \(failed.joined(separator: " and ")) call fell over. Raw reply coming up. " + main
        }
        clips.append(PlannedClip(text: SpeechText.cap(main, limit: mainCap), role: .main, tone: tone))
        return clips
    }

    /// nil when no classifier was wanted or it failed; a failure is logged and never spoken.
    private func tone(of text: String, classifier: (any ToneClassifier)?) async -> Tone? {
        guard let classifier else { return nil }
        do {
            let tone = try await classifier.classify(text)
            Log.log("tone: \(tone.rawValue)")
            return tone
        } catch {
            Log.log("tone error: \(error)")
            return nil
        }
    }

    /// nil when no preamble was wanted or the model returned nothing usable; a failure only when the call threw.
    private func preamble(for text: String, persona: Persona?) async -> Result<String?, RoleFailure> {
        guard let persona else { return .success(nil) }
        do {
            let raw = try await llm.complete(system: Prompts.preamble(persona: persona), user: text)
            var line = SpeechText.firstLine(raw)
            if line != raw.trimmingCharacters(in: .whitespacesAndNewlines) {
                Log.log("preamble guard: multi-line output, kept first line")
            }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            while let last = line.last, ".,!?;:".contains(last) { line.removeLast() }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                Log.log("preamble: model returned empty content, no preamble")
                return .success(nil)
            }
            Log.log("preamble: \(line)")
            return .success(line)
        } catch {
            Log.log("preamble error: \(error)")
            return .failure(RoleFailure(name: "preamble"))
        }
    }

    /// The raw text when short or when the model returned nothing; a failure only when the call threw.
    private func summary(of text: String, persona: Persona?, markupHint: String?) async -> Result<String, RoleFailure> {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words > Self.summaryWordThreshold else { return .success(text) }
        do {
            let raw = try await llm.complete(system: Prompts.summary(preservingVoiceOf: persona, markupHint: markupHint), user: text)
            let rewritten = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewritten.isEmpty else { return .success(text) }
            Log.log("summary: \(words) words to \(rewritten.split(whereSeparator: \.isWhitespace).count)")
            return .success(rewritten)
        } catch {
            Log.log("summary error: \(error)")
            return .failure(RoleFailure(name: "summariser"))
        }
    }
}

private struct RoleFailure: Error {
    let name: String
}

private extension Result where Failure == RoleFailure {
    var failedName: String? {
        if case .failure(let failure) = self { return failure.name }
        return nil
    }
}
