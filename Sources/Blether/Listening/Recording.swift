import Foundation
import Synchronization

/// What the ears need from a microphone. `Microphone` is the real one; tests drive a fake.
@MainActor
protocol MicrophoneSource: AnyObject {
    func start(deviceID: String?, onSamples: @escaping @Sendable ([Float]) -> Void) throws -> Microphone.Choice
    func stop()
}

extension Microphone: MicrophoneSource {}

/// One attempt to hear a reply: opens the mic, feeds the silence detector on the audio thread, and
/// finishes exactly once with everything heard, or with why it gave up. Sounds mark the three moments.
@MainActor
final class Recording {
    enum Outcome: Equatable, Sendable {
        case transcribe([Float])
        case cancelled(String)
    }

    /// Detector and samples live on the audio thread behind a lock; the verdict hops to the main actor.
    private struct Heard {
        var detector = SilenceDetector()
        var samples: [Float] = []
        var settled = false
    }

    /// Mutex cannot be copied into a closure, so the tap captures this box instead.
    private final class HeardBox: Sendable {
        let state = Mutex(Heard())
    }

    private let microphone: any MicrophoneSource
    private let sounds: any Sounds
    private let deviceID: String?
    private let completion: @MainActor (Outcome) -> Void
    private let heard = HeardBox()
    private var finished = false

    init(microphone: any MicrophoneSource, sounds: any Sounds, deviceID: String?, trailingSilence: TimeInterval = SilenceDetector.defaultTrailingSilence, completion: @escaping @MainActor (Outcome) -> Void) {
        self.microphone = microphone
        self.sounds = sounds
        self.deviceID = deviceID
        self.completion = completion
        heard.state.withLock { $0.detector = SilenceDetector(trailingSilence: trailingSilence) }
    }

    /// Opens the mic and plays the armed cue. Throws, with no cue, if the mic will not open.
    func start() throws -> Microphone.Choice {
        let heard = heard
        let choice = try microphone.start(deviceID: deviceID) { [weak self] chunk in
            let verdict: SilenceDetector.Verdict? = heard.state.withLock { state in
                guard !state.settled else { return nil }
                state.samples.append(contentsOf: chunk)
                let verdict = state.detector.feed(chunk)
                if verdict != .listening { state.settled = true }
                return verdict
            }
            guard let verdict, verdict != .listening else { return }
            Task { @MainActor in self?.finish(with: verdict) }
        }
        sounds.play(.armed)
        return choice
    }

    /// From outside: the stop hotkey, or listening switched off. Plays the cancelled cue.
    func cancel() {
        finish(with: .cancel(reason: "stopped"))
    }

    /// Cuts the silence off both ends; the model wants the words, not the room before and after them.
    nonisolated static func trim(_ samples: [Float], to range: ClosedRange<TimeInterval>?) -> [Float] {
        guard let range else { return samples }
        let start = min(samples.count, Int(range.lowerBound * Microphone.sampleRate))
        let end = min(samples.count, Int(range.upperBound * Microphone.sampleRate))
        return Array(samples[start..<max(start, end)])
    }

    private func finish(with verdict: SilenceDetector.Verdict) {
        guard !finished else { return }
        finished = true
        microphone.stop()
        let (samples, detector) = heard.state.withLock { state in
            state.settled = true
            return (state.samples, state.detector)
        }
        let seconds = String(format: "%.1f", detector.elapsed)
        let peak = String(format: "%.3f", detector.peakRMS)
        switch verdict {
        case .send:
            let kept = Self.trim(samples, to: detector.speechRange)
            Log.log("recording sent after \(seconds) s, peak RMS \(peak), kept \(String(format: "%.1f", Double(kept.count) / Microphone.sampleRate)) s of speech")
            sounds.play(.sent)
            completion(.transcribe(kept))
        case .cancel(let reason):
            Log.log("recording cancelled (\(reason)) after \(seconds) s, peak RMS \(peak)")
            sounds.play(.cancelled)
            completion(.cancelled(reason))
        case .listening:
            return
        }
    }
}
