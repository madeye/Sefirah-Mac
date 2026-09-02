import CoreMedia
import Foundation

public enum SampleBufferError: Error, Equatable, Sendable {
    case osStatus(OSStatus)
}

public enum SampleBufferFactory {
    /// Wraps a length-prefixed access unit in a ready-to-decode sample: pts in µs,
    /// `DisplayImmediately` (no timebase, lowest latency) and `NotSync` for non-keyframes.
    public static func make(avcc: Data, format: CMFormatDescription, ptsMicros: UInt64, keyFrame: Bool) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let count = avcc.count
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        guard status == noErr, let block else { throw SampleBufferError.osStatus(status) }
        status = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard status == noErr else { throw SampleBufferError.osStatus(status) }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(ptsMicros), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw SampleBufferError.osStatus(status) }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0
        {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            if !keyFrame {
                CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return sample
    }

    public static func attachment(_ sample: CMSampleBuffer, _ key: CFString) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false),
              CFArrayGetCount(attachments) > 0
        else { return false }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
        guard let value = CFDictionaryGetValue(dict, Unmanaged.passUnretained(key).toOpaque()) else { return false }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }
}
