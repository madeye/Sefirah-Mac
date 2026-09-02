import AVFoundation
import Foundation

/// Receives the audio socket's packets from the audio task (synchronous, one caller at a time);
/// implementations must be thread-safe internally.
public protocol AudioSink: AnyObject, Sendable {
    func configure(codec: StreamCodecID, config: Data?)
    func enqueue(packet: Data)
    func stop()
}

/// Interleaved Float32 ring buffer with scrcpy-style latency control (pure; unit-tested).
///
/// - `push`: appends samples; when more than `2 × target` frames are buffered the oldest are
///   dropped down to `target` (the stream is arrival-paced, so a growing backlog is pure latency).
/// - `pop`: fills `frames` frames; on underrun it outputs silence, marks the buffer "unprimed" and
///   keeps outputting silence until `target / 2` frames have accumulated (avoids stutter loops).
public final class PCMRingBuffer: @unchecked Sendable {
    public struct Stats: Equatable, Sendable {
        public var bufferedFrames = 0
        public var underruns = 0
        public var droppedFrames = 0
        public var pushedFrames = 0
        public var renderedFrames = 0
    }

    public let channels: Int
    public private(set) var targetFrames: Int
    private let lock = NSLock()
    private var samples: [Float] = []
    private var primed = false
    private var stats = Stats()

    public init(channels: Int = 2, targetFrames: Int) {
        self.channels = channels
        self.targetFrames = max(1, targetFrames)
    }

    public var statistics: Stats {
        lock.withLock { stats.bufferedFrames = samples.count / channels; return stats }
    }

    public func push(_ new: [Float]) {
        guard !new.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        samples.append(contentsOf: new)
        stats.pushedFrames += new.count / channels
        let buffered = samples.count / channels
        if buffered > 2 * targetFrames {
            let drop = buffered - targetFrames
            samples.removeFirst(drop * channels)
            stats.droppedFrames += drop
        }
    }

    /// Writes `frames × channels` samples into `out`; returns false when silence was written.
    @discardableResult
    public func pop(into out: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let wanted = frames * channels
        let buffered = samples.count / channels
        if !primed {
            if buffered >= targetFrames / 2 { primed = true } else {
                out.initialize(repeating: 0, count: wanted)
                return false
            }
        }
        if samples.count < wanted {
            out.initialize(repeating: 0, count: wanted)
            samples.removeAll(keepingCapacity: true)
            primed = false
            stats.underruns += 1
            return false
        }
        samples.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: wanted) }
        samples.removeFirst(wanted)
        stats.renderedFrames += frames
        return true
    }

    public func clear() {
        lock.withLock { samples.removeAll(); primed = false }
    }
}

/// `AudioSink` backed by `AVAudioEngine` + `AVAudioSourceNode`: decodes packets on the caller's
/// thread and renders from the ring buffer on the audio thread.
public final class AudioPlayer: AudioSink, @unchecked Sendable {
    public struct Stats: Equatable, Sendable {
        public var codec: StreamCodecID?
        public var packets = 0
        public var decodedFrames = 0
        public var decodeErrors = 0
        public var engineRunning = false
        public var buffer = PCMRingBuffer.Stats()
    }

    public let targetLatencyMs: Int
    /// Decoder / engine problems, reported once each (hooked to the UI banner).
    public var onError: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private let ring: PCMRingBuffer
    private let startEngine: Bool
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    /// Interleaved scratch for the render callback (allocated once; no allocation on the audio thread).
    private let scratchFrames = 8192
    private let scratch: UnsafeMutablePointer<Float>
    private var decoder: AudioDecoder?
    private var muted = false
    private var packets = 0
    private var decodeErrors = 0
    private var reportedDecodeError = false

    /// - Parameter startEngine: false in unit tests (no output device needed).
    public init(targetLatencyMs: Int = 50, startEngine: Bool = true) {
        self.targetLatencyMs = max(5, targetLatencyMs)
        self.startEngine = startEngine
        ring = PCMRingBuffer(channels: Int(AudioDecoder.channels), targetFrames: Int(Double(self.targetLatencyMs) * AudioDecoder.sampleRate / 1000))
        scratch = .allocate(capacity: scratchFrames * Int(AudioDecoder.channels))
        scratch.initialize(repeating: 0, count: scratchFrames * Int(AudioDecoder.channels))
    }

    deinit {
        engine?.stop()
        scratch.deallocate()
    }

    public var isMuted: Bool {
        get { lock.withLock { muted } }
        set { lock.withLock { muted = newValue }; if newValue { ring.clear() } }
    }

    public var statistics: Stats {
        lock.lock()
        var s = Stats(codec: decoder?.codec, packets: packets, decodedFrames: decoder?.decodedFrames ?? 0,
                      decodeErrors: decodeErrors, engineRunning: engine?.isRunning ?? false)
        lock.unlock()
        s.buffer = ring.statistics
        return s
    }

    // MARK: AudioSink

    public func configure(codec: StreamCodecID, config: Data?) {
        lock.lock()
        do {
            decoder = try AudioDecoder(codec: codec, config: config)
            packets = 0
            decodeErrors = 0
            reportedDecodeError = false
        } catch {
            decoder = nil
            lock.unlock()
            onError?("Audio decoder unavailable (\(codec.displayName)): \(error)")
            return
        }
        lock.unlock()
        ring.clear()
        if startEngine { ensureEngine() }
    }

    public func enqueue(packet: Data) {
        lock.lock()
        guard let decoder else { lock.unlock(); return }
        packets += 1
        let muted = self.muted
        var samples: [Float] = []
        var failure: String?
        do {
            samples = try decoder.decode(packet)
        } catch {
            decodeErrors += 1
            if !reportedDecodeError { reportedDecodeError = true; failure = "\(error)" }
        }
        lock.unlock()
        if let failure { onError?("Audio decode failed: \(failure)") }
        if !muted, !samples.isEmpty { ring.push(samples) }
    }

    public func stop() {
        lock.lock()
        let engine = self.engine
        self.engine = nil
        self.source = nil
        self.decoder = nil
        packets = 0
        lock.unlock()
        engine?.stop()
        ring.clear()
    }

    // MARK: Engine

    private func ensureEngine() {
        lock.lock()
        if let engine, engine.isRunning { lock.unlock(); return }
        let engine = AVAudioEngine()
        let ring = self.ring
        let scratch = self.scratch
        let scratchFrames = self.scratchFrames
        let channels = Int(AudioDecoder.channels)
        // The mixer input bus only accepts the standard (deinterleaved) layout; the ring buffer is
        // interleaved, so pop into scratch and split per channel.
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioDecoder.sampleRate, channels: AudioDecoder.channels)!
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = min(Int(frameCount), scratchFrames)
            ring.pop(into: scratch, frames: frames)
            for (channel, buffer) in abl.enumerated() where channel < channels {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<frames { data[i] = scratch[i * channels + channel] }
                if frames < Int(frameCount) { (data + frames).initialize(repeating: 0, count: Int(frameCount) - frames) }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.source = source
        lock.unlock()
        do {
            try engine.start()
        } catch {
            onError?("Audio output unavailable: \(error.localizedDescription)")
        }
    }
}
