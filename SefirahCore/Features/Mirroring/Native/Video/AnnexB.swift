import Foundation

/// H.264 / H.265 parameter sets extracted from an Annex-B config packet.
public struct ParameterSets: Equatable, Sendable {
    public var vps: [Data] = []
    public var sps: [Data] = []
    public var pps: [Data] = []

    public init(vps: [Data] = [], sps: [Data] = [], pps: [Data] = []) {
        self.vps = vps
        self.sps = sps
        self.pps = pps
    }
}

/// Pure Annex-B helpers (start-code delimited NAL units).
public enum AnnexB {
    /// Splits on 3- or 4-byte start codes; returns NAL units without start codes (empty units dropped).
    public static func nalUnits(_ data: Data) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        let n = bytes.count
        var i = 0
        var current: Int? = nil
        while i + 2 < n {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                if let start = current {
                    var end = i
                    // Trailing zeros belong to the (4-byte) start code / trailing_zero_8bits, not the NAL.
                    while end > start, bytes[end - 1] == 0 { end -= 1 }
                    if end > start { units.append(Data(bytes[start..<end])) }
                }
                i += 3
                current = i
            } else {
                i += 1
            }
        }
        if let start = current {
            var end = n
            while end > start, bytes[end - 1] == 0 { end -= 1 }
            if end > start { units.append(Data(bytes[start..<end])) }
        }
        return units
    }

    public static func parameterSets(_ data: Data, codec: StreamCodecID) -> ParameterSets? {
        var sets = ParameterSets()
        for nal in nalUnits(data) {
            guard let first = nal.first else { continue }
            switch codec {
            case .h264:
                switch first & 0x1f {
                case 7: sets.sps.append(nal)
                case 8: sets.pps.append(nal)
                default: break
                }
            case .h265:
                switch (first >> 1) & 0x3f {
                case 32: sets.vps.append(nal)
                case 33: sets.sps.append(nal)
                case 34: sets.pps.append(nal)
                default: break
                }
            default:
                return nil
            }
        }
        if codec == .h264, !sets.sps.isEmpty, !sets.pps.isEmpty { return sets }
        if codec == .h265, !sets.vps.isEmpty, !sets.sps.isEmpty, !sets.pps.isEmpty { return sets }
        return nil
    }

    /// Annex-B → length-prefixed (4-byte big-endian per NAL). All NALs pass through.
    public static func toAVCC(_ data: Data) -> Data {
        var out = Data(capacity: data.count + 8)
        for nal in nalUnits(data) {
            BigEndian.append(UInt32(nal.count), to: &out)
            out.append(nal)
        }
        return out
    }
}
