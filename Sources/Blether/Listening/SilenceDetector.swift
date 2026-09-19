import Foundation

/// Decides when the person has stopped talking. Pure: fed 32 ms chunks, keeps time by counting them,
/// so tests are deterministic and a slow audio thread cannot skew the clock.
struct SilenceDetector {
    enum Verdict: Equatable {
        case listening
        case send
        case cancel(reason: String)
    }

    /// RMS above this is speech. Spike C (blether-ZP9vQ) measured a peak of 0.05 for a normal spoken
    /// "hello" on the built-in mic, so 0.01 RMS is the starting point; `peakRMS` is logged at the end of
    /// every recording to tune it from real rooms.
    static let threshold: Float = 0.01
    /// Trailing quiet that ends a recording once speech has been heard.
    static let trailingSilence: TimeInterval = 2.5
    /// With no speech at all, give up after this long.
    static let noSpeechTimeout: TimeInterval = 15
    /// Nobody talks to Claude for longer than this in one go.
    static let maximumLength: TimeInterval = 90

    /// Canary returns nothing at all for a clip that opens or closes with more than about a second of
    /// digital silence (verified 2026-09-19 on a real recording, blether-ZP9vQ), so recordings are cut
    /// to the speech plus this much either side.
    static let margin: TimeInterval = 0.3

    let secondsPerChunk: TimeInterval
    private(set) var elapsed: TimeInterval = 0
    /// The end of the first and last chunks that counted as speech.
    private(set) var firstSpeechAt: TimeInterval?
    private(set) var lastSpeechAt: TimeInterval?
    private(set) var peakRMS: Float = 0

    init(chunkSize: Int = Microphone.chunkSize, sampleRate: Double = Microphone.sampleRate) {
        secondsPerChunk = Double(chunkSize) / sampleRate
    }

    var heardSpeech: Bool { lastSpeechAt != nil }

    mutating func feed(_ chunk: [Float]) -> Verdict {
        elapsed += secondsPerChunk
        let rms = Self.rms(chunk)
        peakRMS = max(peakRMS, rms)
        if rms > Self.threshold {
            lastSpeechAt = elapsed
            if firstSpeechAt == nil { firstSpeechAt = elapsed }
        }
        if elapsed >= Self.maximumLength {
            return heardSpeech ? .send : .cancel(reason: "no speech")
        }
        if let lastSpeechAt {
            return elapsed - lastSpeechAt >= Self.trailingSilence ? .send : .listening
        }
        return elapsed >= Self.noSpeechTimeout ? .cancel(reason: "no speech") : .listening
    }

    /// The part of the recording worth transcribing: from just before the first speech chunk to just
    /// after the last, in seconds from the start. nil when no speech was heard.
    var speechRange: ClosedRange<TimeInterval>? {
        guard let firstSpeechAt, let lastSpeechAt else { return nil }
        return max(0, firstSpeechAt - secondsPerChunk - Self.margin)...(lastSpeechAt + Self.margin)
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}
