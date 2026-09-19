import AVFoundation
import AudioToolbox

enum MicrophoneError: Error {
    case noInput
    case converter
    case engine(Error)
}

/// Records from one input device as 16 kHz mono Float32, the only format the transcriber accepts,
/// in chunks of `chunkSize` samples (32 ms) so a silence detector can count time by chunk.
@MainActor
final class Microphone {
    nonisolated static let sampleRate: Double = 16_000
    nonisolated static let chunkSize = 512

    /// Which device a recording ended up on, for the log and the menubar.
    enum Choice: Equatable, Sendable {
        case systemDefault
        case device(AudioInputDevice)
        /// The stored id was not connected; the system default was used instead.
        case fallback(missingID: String)
    }

    private let devices: @Sendable () -> [AudioInputDevice]
    private var engine: AVAudioEngine?

    /// `devices` is the seam the tests use; the app passes nothing and gets CoreAudio.
    init(devices: @escaping @Sendable () -> [AudioInputDevice] = { AudioInputDevice.all() }) {
        self.devices = devices
    }

    /// Pure: what `start` will do with a stored id. nil is the system default; an id not in the
    /// list falls back to the default rather than failing, so an unplugged mic never blocks a reply.
    nonisolated static func resolve(deviceID: String?, in devices: [AudioInputDevice]) -> Choice {
        guard let deviceID, !deviceID.isEmpty else { return .systemDefault }
        if let device = devices.first(where: { $0.id == deviceID }) { return .device(device) }
        return .fallback(missingID: deviceID)
    }

    /// Opens the device and starts delivering chunks on the audio thread. The first call prompts for
    /// microphone permission (the app's own, NSMicrophoneUsageDescription in project.yml).
    func start(deviceID: String?, onSamples: @escaping @Sendable ([Float]) -> Void) throws -> Choice {
        stop()
        let choice = Self.resolve(deviceID: deviceID, in: devices())
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if case .device(let device) = choice, let id = AudioInputDevice.deviceID(forUID: device.id), let unit = input.audioUnit {
            var deviceID = id
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { Log.log("microphone: could not select \(device.name) (\(status)), using the system default") }
        }
        let native = input.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0 else { throw MicrophoneError.noInput }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: native, to: target) else { throw MicrophoneError.converter }
        let tap = Tap(converter: converter, target: target, onSamples: onSamples)
        // The tap runs on the audio thread: the closure must be @Sendable and touch nothing on this actor.
        input.installTap(onBus: 0, bufferSize: 4096, format: native) { @Sendable buffer, _ in
            tap.handle(buffer)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophoneError.engine(error)
        }
        self.engine = engine
        Log.log("microphone: \(native.sampleRate) Hz \(native.channelCount) ch in, \(Self.describe(choice))")
        return choice
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    nonisolated static func describe(_ choice: Choice) -> String {
        switch choice {
        case .systemDefault: "system default microphone"
        case .device(let device): "microphone \(device.name)"
        case .fallback(let id): "microphone \(id) not connected, using the system default"
        }
    }

    /// Owned by the tap closure and called only from AVFoundation's serial tap queue; hence unchecked.
    private final class Tap: @unchecked Sendable {
        private let converter: AVAudioConverter
        private let target: AVAudioFormat
        private let onSamples: @Sendable ([Float]) -> Void
        private var chunker = SampleChunker(size: Microphone.chunkSize)

        init(converter: AVAudioConverter, target: AVAudioFormat, onSamples: @escaping @Sendable ([Float]) -> Void) {
            self.converter = converter
            self.target = target
            self.onSamples = onSamples
        }

        func handle(_ buffer: AVAudioPCMBuffer) {
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let data = out.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            for chunk in chunker.append(samples) { onSamples(chunk) }
        }
    }
}

/// Re-cuts a stream of samples into fixed-size chunks, carrying the remainder between calls.
struct SampleChunker {
    let size: Int
    private var carry: [Float] = []

    init(size: Int) { self.size = size }

    mutating func append(_ samples: [Float]) -> [[Float]] {
        carry.append(contentsOf: samples)
        var chunks: [[Float]] = []
        while carry.count >= size {
            chunks.append(Array(carry.prefix(size)))
            carry.removeFirst(size)
        }
        return chunks
    }
}
