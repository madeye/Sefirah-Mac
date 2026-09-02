import CoreMedia
import Foundation
@testable import SefirahCore
import XCTest

final class AnnexBTests: XCTestCase {
    func testStartCodes() {
        let units = AnnexB.nalUnits(Hex.data("00000001 6701 000001 6802 00000001 65ff00"))
        XCTAssertEqual(units.map(Hex.string), ["6701", "6802", "65ff"], "trailing zeros are not part of a NAL")
        XCTAssertEqual(AnnexB.nalUnits(Data()), [])
        XCTAssertEqual(AnnexB.nalUnits(Hex.data("6701")), [], "no start code → nothing")
        XCTAssertEqual(AnnexB.nalUnits(Hex.data("00000001")), [])
    }

    func testH264ParameterSetsFromXiaomiConfig() throws {
        let sets = try XCTUnwrap(AnnexB.parameterSets(Fixtures.h264Config, codec: .h264))
        XCTAssertEqual(sets.sps.map(Hex.string), ["67640020acb4048050d3505060506d0a1350"])
        XCTAssertEqual(sets.pps.map(Hex.string), ["68ee06f2c0"])
        XCTAssertTrue(sets.vps.isEmpty)
    }

    func testHEVCParameterSets() throws {
        let sets = try XCTUnwrap(AnnexB.parameterSets(Fixtures.h265Config, codec: .h265))
        XCTAssertEqual(sets.vps.count, 1)
        XCTAssertEqual(sets.sps.count, 1)
        XCTAssertEqual(sets.pps.count, 1)
        XCTAssertEqual(sets.vps[0].prefix(2), Hex.data("4001"))
        XCTAssertEqual(sets.sps[0].prefix(2), Hex.data("4201"))
        XCTAssertEqual(sets.pps[0].prefix(2), Hex.data("4401"))
    }

    func testIncompleteSetsReturnNil() {
        XCTAssertNil(AnnexB.parameterSets(Hex.data("00000001 67640020"), codec: .h264))
        XCTAssertNil(AnnexB.parameterSets(Fixtures.h264Config, codec: .h265))
        XCTAssertNil(AnnexB.parameterSets(Fixtures.h264Config, codec: .opus))
    }

    func testToAVCC() {
        XCTAssertEqual(Hex.string(AnnexB.toAVCC(Hex.data("00000001 6701 000001 65aabb"))), "000000026701" + "0000000365aabb")
        XCTAssertEqual(AnnexB.toAVCC(Fixtures.h264KeyFrame).prefix(4), Hex.data("000000b1"))
    }
}

final class VideoFormatTests: XCTestCase {
    func testH264FormatFromCapturedSets() throws {
        let sets = try XCTUnwrap(AnnexB.parameterSets(Fixtures.h264Config, codec: .h264))
        let format = try VideoFormat.make(sets, codec: .h264)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264)
        let dims = VideoFormat.dimensions(format)
        XCTAssertEqual(dims.width, 576)
        XCTAssertEqual(dims.height, 1280)
    }

    func testHEVCFormatFromCapturedSets() throws {
        let sets = try XCTUnwrap(AnnexB.parameterSets(Fixtures.h265Config, codec: .h265))
        let format = try VideoFormat.make(sets, codec: .h265)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_HEVC)
        let dims = VideoFormat.dimensions(format)
        XCTAssertEqual(dims.width, 576)
        XCTAssertEqual(dims.height, 1280)
    }

    func testErrors() {
        XCTAssertThrowsError(try VideoFormat.make(ParameterSets(), codec: .h264)) { XCTAssertEqual($0 as? VideoFormatError, .noParameterSets) }
        XCTAssertThrowsError(try VideoFormat.make(ParameterSets(sps: [Data([1])], pps: [Data([1])]), codec: .vp8)) {
            XCTAssertEqual($0 as? VideoFormatError, .unsupportedCodec)
        }
    }
}

final class SampleBufferFactoryTests: XCTestCase {
    func testKeyFrameSample() throws {
        let sets = try XCTUnwrap(AnnexB.parameterSets(Fixtures.h264Config, codec: .h264))
        let format = try VideoFormat.make(sets, codec: .h264)
        let avcc = AnnexB.toAVCC(Fixtures.h264KeyFrame)
        let sample = try SampleBufferFactory.make(avcc: avcc, format: format, ptsMicros: 28_513_108_121, keyFrame: true)
        XCTAssertEqual(CMSampleBufferGetTotalSampleSize(sample), 181)
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        XCTAssertEqual(pts.value, 28_513_108_121)
        XCTAssertEqual(pts.timescale, 1_000_000)
        XCTAssertTrue(SampleBufferFactory.attachment(sample, kCMSampleAttachmentKey_DisplayImmediately))
        XCTAssertFalse(SampleBufferFactory.attachment(sample, kCMSampleAttachmentKey_NotSync))
        XCTAssertTrue(CMSampleBufferDataIsReady(sample))
        // Payload round-trips.
        let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer), noErr)
        XCTAssertEqual(Data(bytes: try XCTUnwrap(pointer), count: length), avcc)
    }

    func testNonKeyFrameIsNotSync() throws {
        let sets = try XCTUnwrap(AnnexB.parameterSets(Fixtures.h264Config, codec: .h264))
        let format = try VideoFormat.make(sets, codec: .h264)
        let sample = try SampleBufferFactory.make(avcc: Hex.data("00000002 4100"), format: format, ptsMicros: 7, keyFrame: false)
        XCTAssertTrue(SampleBufferFactory.attachment(sample, kCMSampleAttachmentKey_NotSync))
        XCTAssertTrue(SampleBufferFactory.attachment(sample, kCMSampleAttachmentKey_DisplayImmediately))
    }
}
