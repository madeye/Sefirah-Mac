import Foundation

/// The 4-byte codec id that starts the video and audio sockets (`S/video/VideoCodec.java`, `S/audio/AudioCodec.java`).
public enum StreamCodecID: Equatable, Sendable {
    case h264, h265, av1, vp8, vp9
    case opus, aac, flac, raw
    /// Audio only: the device cannot capture; continue without audio.
    case disabled
    /// Fatal configuration error.
    case configError
    case unknown(UInt32)

    public init(rawValue: UInt32) {
        switch rawValue {
        case 0x6832_3634: self = .h264
        case 0x6832_3635: self = .h265
        case 0x0061_7631: self = .av1
        case 0x0076_7038: self = .vp8
        case 0x0076_7039: self = .vp9
        case 0x6f70_7573: self = .opus
        case 0x0061_6163: self = .aac
        case 0x666c_6163: self = .flac
        case 0x0072_6177: self = .raw
        case 0: self = .disabled
        case 1: self = .configError
        default: self = .unknown(rawValue)
        }
    }

    public init(_ data: Data) {
        self.init(rawValue: BigEndian.u32(data, at: 0))
    }

    public var isVideo: Bool {
        switch self {
        case .h264, .h265, .av1, .vp8, .vp9: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .h265: return "H.265"
        case .av1: return "AV1"
        case .vp8: return "VP8"
        case .vp9: return "VP9"
        case .opus: return "Opus"
        case .aac: return "AAC"
        case .flac: return "FLAC"
        case .raw: return "PCM"
        case .disabled: return "disabled"
        case .configError: return "config error"
        case .unknown(let v): return String(format: "0x%08x", v)
        }
    }
}

public enum MediaPacketError: Error, Equatable, Sendable {
    case shortHeader(Int)
    case zeroSize
    case notSessionPacket
    case zeroDimensions
}

/// Video-only 12-byte packet emitted first and on every encoder reset (`S/device/Streamer.java`).
public struct SessionHeader: Equatable, Sendable {
    public static let size = 12
    public var width: Int
    public var height: Int
    public var clientResized: Bool

    public init(width: Int, height: Int, clientResized: Bool) {
        self.width = width
        self.height = height
        self.clientResized = clientResized
    }

    /// Bit 31 of the first u32 (byte0 & 0x80).
    public static func isSession(_ header: Data) -> Bool {
        header.count >= 1 && (header[header.startIndex] & 0x80) != 0
    }

    public static func parse(_ header: Data) throws -> SessionHeader {
        guard header.count >= size else { throw MediaPacketError.shortHeader(header.count) }
        guard isSession(header) else { throw MediaPacketError.notSessionPacket }
        let flags = BigEndian.u32(header, at: 0)
        let width = Int(BigEndian.u32(header, at: 4))
        let height = Int(BigEndian.u32(header, at: 8))
        guard width > 0, height > 0 else { throw MediaPacketError.zeroDimensions }
        return SessionHeader(width: width, height: height, clientResized: (flags & 0x1) != 0)
    }
}

/// 12-byte media packet header: u64 pts_and_flags, u32 size.
public struct MediaPacketHeader: Equatable, Sendable {
    public static let size = 12
    public static let flagSession: UInt64 = 1 << 63
    public static let flagConfig: UInt64 = 1 << 62
    public static let flagKeyFrame: UInt64 = 1 << 61
    public static let ptsMask: UInt64 = (1 << 61) - 1

    /// Microseconds (SystemClock-based, not zero-based).
    public var pts: UInt64
    public var isConfig: Bool
    public var isKeyFrame: Bool
    public var size: Int

    public init(pts: UInt64, isConfig: Bool, isKeyFrame: Bool, size: Int) {
        self.pts = pts
        self.isConfig = isConfig
        self.isKeyFrame = isKeyFrame
        self.size = size
    }

    public static func parse(_ header: Data) throws -> MediaPacketHeader {
        guard header.count >= size else { throw MediaPacketError.shortHeader(header.count) }
        let ptsAndFlags = BigEndian.u64(header, at: 0)
        let size = Int(BigEndian.u32(header, at: 8))
        guard size > 0 else { throw MediaPacketError.zeroSize }
        return MediaPacketHeader(
            pts: ptsAndFlags & ptsMask,
            isConfig: ptsAndFlags & flagConfig != 0,
            isKeyFrame: ptsAndFlags & flagKeyFrame != 0,
            size: size
        )
    }
}

/// Index-safe big-endian readers (offsets are relative to `data.startIndex`).
public enum BigEndian {
    public static func u16(_ data: Data, at offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) << 8 | UInt16(data[i + 1])
    }

    public static func u32(_ data: Data, at offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }

    public static func u64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(u32(data, at: offset)) << 32 | UInt64(u32(data, at: offset + 4))
    }

    public static func append(_ v: UInt16, to data: inout Data) {
        data.append(UInt8(v >> 8)); data.append(UInt8(v & 0xff))
    }

    public static func append(_ v: UInt32, to data: inout Data) {
        append(UInt16(v >> 16), to: &data); append(UInt16(v & 0xffff), to: &data)
    }

    public static func append(_ v: UInt64, to data: inout Data) {
        append(UInt32(v >> 32), to: &data); append(UInt32(v & 0xffff_ffff), to: &data)
    }

    public static func append(_ v: Int32, to data: inout Data) { append(UInt32(bitPattern: v), to: &data) }
    public static func append(_ v: Int16, to data: inout Data) { append(UInt16(bitPattern: v), to: &data) }
}
