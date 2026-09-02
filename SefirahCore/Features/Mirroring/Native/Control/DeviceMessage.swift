import Foundation

/// Server → client messages (`S/device/DeviceMessage.java`).
public enum DeviceMessage: Equatable, Sendable {
    case clipboard(String)
    case ackClipboard(UInt64)
    case uhidOutput(id: UInt16, data: Data)

    public enum ParseError: Error, Equatable, Sendable {
        case unknownType(UInt8)
        case oversize(Int)
    }

    public static let maxClipboardBytes = 262_144

    /// Incremental parser: nil when more bytes are needed; otherwise the message and the bytes consumed.
    public static func parse(_ buffer: Data) throws -> (DeviceMessage, consumed: Int)? {
        guard let type = buffer.first else { return nil }
        switch type {
        case 0:
            guard buffer.count >= 5 else { return nil }
            let len = Int(BigEndian.u32(buffer, at: 1))
            guard len <= maxClipboardBytes else { throw ParseError.oversize(len) }
            guard buffer.count >= 5 + len else { return nil }
            let start = buffer.startIndex + 5
            let text = String(decoding: buffer[start..<(start + len)], as: UTF8.self)
            return (.clipboard(text), 5 + len)
        case 1:
            guard buffer.count >= 9 else { return nil }
            return (.ackClipboard(BigEndian.u64(buffer, at: 1)), 9)
        case 2:
            guard buffer.count >= 5 else { return nil }
            let id = BigEndian.u16(buffer, at: 1)
            let size = Int(BigEndian.u16(buffer, at: 3))
            guard buffer.count >= 5 + size else { return nil }
            let start = buffer.startIndex + 5
            return (.uhidOutput(id: id, data: Data(buffer[start..<(start + size)])), 5 + size)
        default:
            throw ParseError.unknownType(type)
        }
    }
}
