import SefirahCore
import XCTest

final class UDPDiscoveryTests: XCTestCase {
    func testBroadcastReceivedOnLoopback() throws {
        let queue = DispatchQueue(label: "udp-test")
        // Not the real discovery port: a running Sefirah (or a phone on the LAN)
        // broadcasting on 5149 would otherwise be picked up by the receiver.
        let port: UInt16 = 51_490
        let receiver = UDPDiscovery(port: port, localDeviceId: "receiver", queue: queue)
        let sender = UDPDiscovery(port: port, localDeviceId: "sender", queue: queue)
        let received = expectation(description: "udp")
        receiver.onBroadcast = { broadcast, host in
            XCTAssertEqual(broadcast.deviceId, "sender")
            XCTAssertEqual(broadcast.port, 5153)
            XCTAssertFalse(host.isEmpty)
            received.fulfill()
        }
        try receiver.start()
        try sender.start()
        defer {
            sender.stop()
            receiver.stop()
        }
        sender.send(
            UdpBroadcast(port: 5153, deviceId: "sender", deviceName: "Sender"),
            to: ["127.0.0.1"]
        )
        wait(for: [received], timeout: 3)
    }

    func testParseBroadcastAcceptsMissingTypeDiscriminator() throws {
        let withType = try NDJSONCodec.encodeMessage(
            .udpBroadcast(UdpBroadcast(port: 5150, deviceId: "phone", deviceName: "Pixel"))
        )
        XCTAssertEqual(UDPDiscovery.parseBroadcast(withType)?.deviceId, "phone")

        let withoutType = Data(#"{"port":5151,"deviceId":"p2","deviceName":"Xiaomi"}"#.utf8)
        let parsed = UDPDiscovery.parseBroadcast(withoutType)
        XCTAssertEqual(parsed?.port, 5151)
        XCTAssertEqual(parsed?.deviceId, "p2")
    }
}
