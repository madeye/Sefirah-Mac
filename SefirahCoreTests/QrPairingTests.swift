import SefirahCore
import XCTest

final class QrPairingTests: XCTestCase {
    func testDeepLinkRoundTrip() throws {
        let payload = QrCodePayload(
            addresses: ["192.168.1.8", "10.0.0.2"],
            port: 5150,
            deviceId: "abc-123",
            deviceName: "Studio"
        )
        let link = try payload.deepLink()
        XCTAssertTrue(link.hasPrefix("sefirah://pair?data="))
        XCTAssertFalse(link.contains(" "), "data must be percent-encoded")
        let parsed = try QrCodePayload.parseDeepLink(link)
        XCTAssertEqual(parsed, payload)
    }

    func testJSONHasCamelCaseKeys() throws {
        let json = try QrCodePayload(
            addresses: ["127.0.0.1"],
            port: 5151,
            deviceId: "id",
            deviceName: "Mac"
        ).jsonString()
        XCTAssertTrue(json.contains("\"addresses\""))
        XCTAssertTrue(json.contains("\"deviceId\""))
        XCTAssertTrue(json.contains("\"deviceName\""))
        XCTAssertFalse(json.contains("\"type\""))
    }

    func testDeepLinkRendersQRImage() throws {
        let link = try QrCodePayload(
            addresses: ["192.168.1.8"],
            port: 5150,
            deviceId: "abc-123",
            deviceName: "Studio"
        ).deepLink()
        let image = QrCodeImage.make(link)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 16)
        XCTAssertGreaterThan(image?.size.height ?? 0, 16)
        XCTAssertNil(QrCodeImage.make(""))
    }

    func testReconnectableAddressDropsLinkLocalAndMappedIPv4() {
        XCTAssertNil(PeerAddress.reconnectable("fe80::18fc:47ff:fed6:f94%en1"))
        XCTAssertNil(PeerAddress.reconnectable("[fe80::1%en0]"))
        XCTAssertNil(PeerAddress.reconnectable("127.0.0.1"))
        XCTAssertEqual(PeerAddress.reconnectable("192.168.1.8"), "192.168.1.8")
        XCTAssertEqual(PeerAddress.normalize("::ffff:10.0.0.2"), "10.0.0.2")
        XCTAssertEqual(PeerAddress.normalize("[::ffff:10.0.0.2]"), "10.0.0.2")
    }
}
