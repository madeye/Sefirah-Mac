import SefirahCore
import XCTest

final class VerificationCodeTests: XCTestCase {
    func testEmptyPeerReturnsSentinel() {
        XCTAssertEqual(
            VerificationCode.compute(localSPKI: Data([0x01]), peerSPKI: Data()),
            "00000000"
        )
        XCTAssertEqual(
            VerificationCode.compute(localSPKI: Data([0x01]), peerPublicKeyBase64: ""),
            "00000000"
        )
    }

    func testOrderIndependent() {
        let a = Data([1, 2, 3])
        let b = Data([1, 2, 4])
        XCTAssertEqual(
            VerificationCode.compute(localSPKI: a, peerSPKI: b),
            VerificationCode.compute(localSPKI: b, peerSPKI: a)
        )
        XCTAssertEqual(VerificationCode.compute(localSPKI: a, peerSPKI: b), "35923652")
    }

    func testEqualInputs() {
        let bytes = Data([9, 9, 9])
        XCTAssertEqual(VerificationCode.compute(localSPKI: bytes, peerSPKI: bytes), "76A3029A")
    }

    func testShorterPrefixIsLessThanLonger() {
        let a = Data([1, 2])
        let b = Data([1, 2, 0])
        XCTAssertEqual(VerificationCode.compareUnsigned(a, b), -1)
        XCTAssertEqual(VerificationCode.compute(localSPKI: a, peerSPKI: b), "9D90E071")
        let concat = VerificationCode.sortedConcatUnsigned(a, b)
        XCTAssertEqual([UInt8](concat), [1, 2, 0, 1, 2])
    }

    func testUnsignedHighBit() {
        let low = Data([0x7F])
        let high = Data([0x80])
        XCTAssertEqual(VerificationCode.compareUnsigned(low, high), -1)
        XCTAssertEqual(VerificationCode.compute(localSPKI: low, peerSPKI: high), "E65ACEB8")
        XCTAssertEqual([UInt8](VerificationCode.sortedConcatUnsigned(low, high)), [0x80, 0x7F])
    }

    func testLongerVector() {
        let a = Data(0..<32)
        let b = Data(32..<64)
        XCTAssertEqual(VerificationCode.compute(localSPKI: a, peerSPKI: b), "84E4BD6C")
        XCTAssertEqual(
            VerificationCode.compute(localSPKI: a, peerSPKI: b),
            VerificationCode.compute(localSPKI: b, peerSPKI: a)
        )
    }

    func testHexIsUppercase() {
        let code = VerificationCode.compute(localSPKI: Data([1, 2, 3]), peerSPKI: Data([1, 2, 4]))
        XCTAssertEqual(code, code.uppercased())
        XCTAssertEqual(code.count, 8)
    }

    func testBase64PeerKey() {
        let local = Data([1, 2, 3])
        let peer = Data([1, 2, 4])
        XCTAssertEqual(
            VerificationCode.compute(localSPKI: local, peerPublicKeyBase64: peer.base64EncodedString()),
            "35923652"
        )
    }
}
