import AudioToolbox
import AVFoundation
import Foundation

/// Decodes scrcpy audio packets (Opus / AAC via `AVAudioConverter`, raw s16le passthrough) into
/// interleaved Float32 stereo 48 kHz samples. Not thread-safe: owned by whoever drives the audio
/// socket (`AudioPlayer` serialises calls with its lock).
public final class AudioDecoder {
    public static let sampleRate: Double = 48_000
    public static let channels: AVAudioChannelCount = 2
    /// Longest Opus packet (120 ms) is 5760 frames; AAC is 1024; raw ≤ 1024.
    static let maxFramesPerPacket: AVAudioFrameCount = 5760

    public enum DecodeError: Error, Equatable, Sendable {
        case unsupportedCodec(String)
        case converterUnavailable(String)
        case conversionFailed(String)
        case oddRawPacket(Int)
    }

    public let codec: StreamCodecID
    /// Interleaved Float32 stereo 48 kHz — what `AudioPlayer`'s ring buffer stores.
    public let outputFormat: AVAudioFormat

    private let converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat?
    private let pcm: AVAudioPCMBuffer?
    private(set) var decodedFrames: Int = 0

    /// - Parameter config: the CONFIG packet payload (Opus `OpusHead`, ignored; AAC 2-byte AudioSpecificConfig; raw: none).
    public init(codec: StreamCodecID, config: Data?) throws {
        self.codec = codec
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: Self.channels, interleaved: true) else {
            throw DecodeError.converterUnavailable("output format")
        }
        outputFormat = out
        switch codec {
        case .raw:
            converter = nil
            inputFormat = nil
            pcm = nil
        case .opus, .aac:
            var asbd = AudioStreamBasicDescription(
                mSampleRate: Self.sampleRate,
                mFormatID: codec == .opus ? kAudioFormatOpus : kAudioFormatMPEG4AAC,
                mFormatFlags: 0, mBytesPerPacket: 0,
                mFramesPerPacket: codec == .opus ? 960 : 1024,
                mBytesPerFrame: 0, mChannelsPerFrame: UInt32(Self.channels), mBitsPerChannel: 0, mReserved: 0
            )
            guard let input = AVAudioFormat(streamDescription: &asbd) else {
                throw DecodeError.converterUnavailable("input format \(codec.displayName)")
            }
            guard let conv = AVAudioConverter(from: input, to: out) else {
                throw DecodeError.converterUnavailable("AVAudioConverter \(codec.displayName) → PCM")
            }
            if codec == .aac, let config, !config.isEmpty { conv.magicCookie = config }
            conv.primeMethod = .none
            converter = conv
            inputFormat = input
            pcm = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: Self.maxFramesPerPacket)
        default:
            throw DecodeError.unsupportedCodec(codec.displayName)
        }
    }

    /// Decodes one media packet. Returns interleaved L/R Float32 samples (may be empty while the
    /// decoder primes, e.g. the Opus pre-skip).
    public func decode(_ packet: Data) throws -> [Float] {
        switch codec {
        case .raw: return try decodeRaw(packet)
        default: return try decodeCompressed(packet)
        }
    }

    private func decodeRaw(_ packet: Data) throws -> [Float] {
        guard packet.count % 4 == 0 else { throw DecodeError.oddRawPacket(packet.count) }
        var out = [Float](repeating: 0, count: packet.count / 2)
        packet.withUnsafeBytes { raw in
            for i in 0..<out.count {
                let s = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                out[i] = Float(s) / 32768
            }
        }
        decodedFrames += out.count / 2
        return out
    }

    private func decodeCompressed(_ packet: Data) throws -> [Float] {
        guard let converter, let inputFormat, let pcm, !packet.isEmpty else { return [] }
        let compressed = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: 1, maximumPacketSize: packet.count)
        packet.withUnsafeBytes { raw in
            compressed.data.copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))

        pcm.frameLength = 0
        var error: NSError?
        var samples: [Float] = []
        // One packet per call; after it is consumed report "no data now" so the converter returns
        // what it has (never `.endOfStream`, which would finalise the converter). The input block is
        // invoked synchronously on this thread, so the box is only ever touched serially.
        let input = InputPacket(compressed)
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            guard let buffer = input.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        switch status {
        case .error:
            throw DecodeError.conversionFailed(error?.localizedDescription ?? "unknown")
        case .haveData, .inputRanDry, .endOfStream:
            let frames = Int(pcm.frameLength)
            if frames > 0, let base = pcm.floatChannelData?.pointee {
                samples = Array(UnsafeBufferPointer(start: base, count: frames * Int(Self.channels)))
            }
        @unknown default:
            break
        }
        decodedFrames += samples.count / Int(Self.channels)
        return samples
    }
}

/// Single-use holder handed to `AVAudioConverter.convert`'s `@Sendable` input block. The block runs
/// synchronously on the calling thread (the decoder is not thread-safe; the caller serialises), so no
/// synchronisation is needed; the wrapper only silences the non-Sendable capture diagnostics.
private final class InputPacket: @unchecked Sendable {
    private var buffer: AVAudioCompressedBuffer?
    init(_ buffer: AVAudioCompressedBuffer) { self.buffer = buffer }
    func take() -> AVAudioCompressedBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
