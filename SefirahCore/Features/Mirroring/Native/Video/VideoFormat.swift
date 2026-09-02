import CoreMedia
import Foundation
import VideoToolbox

public enum VideoFormatError: Error, Equatable, Sendable {
    case noParameterSets
    case osStatus(OSStatus)
    case unsupportedCodec
}

public enum VideoFormat {
    /// AV1 is only offered when the hardware decoder exists.
    public static var av1Supported: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    public static func make(_ sets: ParameterSets, codec: StreamCodecID) throws -> CMFormatDescription {
        switch codec {
        case .h264:
            guard !sets.sps.isEmpty, !sets.pps.isEmpty else { throw VideoFormatError.noParameterSets }
            return try create(sets.sps + sets.pps, hevc: false)
        case .h265:
            guard !sets.vps.isEmpty, !sets.sps.isEmpty, !sets.pps.isEmpty else { throw VideoFormatError.noParameterSets }
            return try create(sets.vps + sets.sps + sets.pps, hevc: true)
        default:
            throw VideoFormatError.unsupportedCodec
        }
    }

    /// AV1: the config packet is the `av1C` box payload.
    public static func makeAV1(config: Data, width: Int, height: Int) throws -> CMFormatDescription {
        var description: CMFormatDescription?
        let atoms: [String: Any] = ["av1C": config as NSData]
        let extensions: [String: Any] = [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: atoms]
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_AV1,
            width: Int32(width), height: Int32(height),
            extensions: extensions as CFDictionary, formatDescriptionOut: &description
        )
        guard status == noErr, let description else { throw VideoFormatError.osStatus(status) }
        return description
    }

    public static func dimensions(_ format: CMFormatDescription) -> (width: Int, height: Int) {
        let d = CMVideoFormatDescriptionGetDimensions(format)
        return (Int(d.width), Int(d.height))
    }

    private static func create(_ sets: [Data], hevc: Bool) throws -> CMFormatDescription {
        let buffers: [UnsafeMutablePointer<UInt8>] = sets.map { set in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(set.count, 1))
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers: [UnsafePointer<UInt8>] = buffers.map { UnsafePointer($0) }
        let sizes: [Int] = sets.map(\.count)
        var description: CMFormatDescription?
        let status: OSStatus = pointers.withUnsafeBufferPointer { pp in
            sizes.withUnsafeBufferPointer { sp in
                if hevc {
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
                        parameterSetPointers: pp.baseAddress!, parameterSetSizes: sp.baseAddress!,
                        nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &description
                    )
                } else {
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
                        parameterSetPointers: pp.baseAddress!, parameterSetSizes: sp.baseAddress!,
                        nalUnitHeaderLength: 4, formatDescriptionOut: &description
                    )
                }
            }
        }
        guard status == noErr, let description else { throw VideoFormatError.osStatus(status) }
        return description
    }
}
