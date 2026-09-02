import Foundation
@testable import SefirahCore
import XCTest

final class MediaPacketTests: XCTestCase {
    func testCodecIDs() {
        XCTAssertEqual(StreamCodecID(Hex.data("68323634")), .h264)
        XCTAssertEqual(StreamCodecID(Hex.data("68323635")), .h265)
        XCTAssertEqual(StreamCodecID(Hex.data("00617631")), .av1)
        XCTAssertEqual(StreamCodecID(Hex.data("00767038")), .vp8)
        XCTAssertEqual(StreamCodecID(Hex.data("00767039")), .vp9)
        XCTAssertEqual(StreamCodecID(Hex.data("6f707573")), .opus)
        XCTAssertEqual(StreamCodecID(Hex.data("00616163")), .aac)
        XCTAssertEqual(StreamCodecID(Hex.data("666c6163")), .flac)
        XCTAssertEqual(StreamCodecID(Hex.data("00726177")), .raw)
        XCTAssertEqual(StreamCodecID(Hex.data("00000000")), .disabled)
        XCTAssertEqual(StreamCodecID(Hex.data("00000001")), .configError)
        XCTAssertEqual(StreamCodecID(Hex.data("deadbeef")), .unknown(0xdead_beef))
        XCTAssertTrue(StreamCodecID.h264.isVideo)
        XCTAssertFalse(StreamCodecID.opus.isVideo)
    }

    func testSessionHeaderObserved() throws {
        let header = Hex.data("80000000 00000240 00000500")
        XCTAssertTrue(SessionHeader.isSession(header))
        let s = try SessionHeader.parse(header)
        XCTAssertEqual(s, SessionHeader(width: 576, height: 1280, clientResized: false))
        XCTAssertTrue(try SessionHeader.parse(Hex.data("80000001 00000320 00000258")).clientResized)
    }

    func testSessionHeaderErrors() {
        XCTAssertThrowsError(try SessionHeader.parse(Hex.data("40000000 00000000 0000001a"))) {
            XCTAssertEqual($0 as? MediaPacketError, .notSessionPacket)
        }
        XCTAssertThrowsError(try SessionHeader.parse(Hex.data("80000000 00000000 00000500"))) {
            XCTAssertEqual($0 as? MediaPacketError, .zeroDimensions)
        }
        XCTAssertThrowsError(try SessionHeader.parse(Hex.data("8000"))) {
            XCTAssertEqual($0 as? MediaPacketError, .shortHeader(2))
        }
        XCTAssertFalse(SessionHeader.isSession(Hex.data("20000000 0001e240 00000010")))
    }

    func testConfigPacket() throws {
        let h = try MediaPacketHeader.parse(Hex.data("40000000 00000000 0000001a"))
        XCTAssertTrue(h.isConfig)
        XCTAssertFalse(h.isKeyFrame)
        XCTAssertEqual(h.pts, 0)
        XCTAssertEqual(h.size, 26)
    }

    func testKeyFrameAndPtsMask() throws {
        let h = try MediaPacketHeader.parse(Hex.data("20000000 0001e240 00000064"))
        XCTAssertTrue(h.isKeyFrame)
        XCTAssertFalse(h.isConfig)
        XCTAssertEqual(h.pts, 123_456)
        XCTAssertEqual(h.size, 100)
        let masked = try MediaPacketHeader.parse(Hex.data("3fffffff ffffffff 00000001"))
        XCTAssertEqual(masked.pts, MediaPacketHeader.ptsMask)
        XCTAssertTrue(masked.isKeyFrame)
        XCTAssertFalse(masked.isConfig)
        let plain = try MediaPacketHeader.parse(Hex.data("00000006 a3d1f2c0 00000200"))
        XCTAssertEqual(plain.pts, 28_518_249_152)
        XCTAssertFalse(plain.isKeyFrame)
    }

    func testZeroSizeRejected() {
        XCTAssertThrowsError(try MediaPacketHeader.parse(Hex.data("20000000 0001e240 00000000"))) {
            XCTAssertEqual($0 as? MediaPacketError, .zeroSize)
        }
    }

    func testBigEndianRoundTrip() {
        var d = Data()
        BigEndian.append(UInt16(0x1234), to: &d)
        BigEndian.append(UInt32(0x8000_0001), to: &d)
        BigEndian.append(UInt64(0x0102_0304_0506_0708), to: &d)
        BigEndian.append(Int32(-1), to: &d)
        BigEndian.append(Int16(-2048), to: &d)
        XCTAssertEqual(Hex.string(d), "1234800000010102030405060708fffffffff800")
        let slice = d[2...]
        XCTAssertEqual(BigEndian.u32(slice, at: 0), 0x8000_0001, "offsets are relative to startIndex")
        XCTAssertEqual(BigEndian.u64(slice, at: 4), 0x0102_0304_0506_0708)
    }
}
