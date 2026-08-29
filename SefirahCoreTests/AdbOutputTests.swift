import SefirahCore
import XCTest

final class AdbOutputTests: XCTestCase {
    func testParseDevices() {
        let out = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        1A2B3C4D               device usb:1-1 product:panther model:Pixel_7 device:panther transport_id:1
        192.168.1.20:5555      device product:panther model:Pixel_7 device:panther transport_id:2
        XYZ                    unauthorized usb:2-1 transport_id:3
        OFF1                   offline transport_id:4

        """
        let devices = AdbOutput.parseDevices(out)
        XCTAssertEqual(devices.count, 4)
        XCTAssertEqual(devices[0], AdbDevice(serial: "1A2B3C4D", state: "device", model: "Pixel_7"))
        XCTAssertEqual(devices[1].serial, "192.168.1.20:5555")
        XCTAssertTrue(devices[1].isTcp)
        XCTAssertFalse(devices[0].isTcp)
        XCTAssertEqual(devices[2], AdbDevice(serial: "XYZ", state: "unauthorized", model: nil))
        XCTAssertEqual(devices[3].state, "offline")
        XCTAssertEqual(AdbOutput.parseDevices("List of devices attached\n\n"), [])
    }

    func testConnectSucceeded() {
        XCTAssertTrue(AdbOutput.connectSucceeded("connected to 192.168.1.20:5555"))
        XCTAssertTrue(AdbOutput.connectSucceeded("already connected to 192.168.1.20:5555"))
        XCTAssertFalse(AdbOutput.connectSucceeded("failed to connect to '192.168.1.20:5555': Connection refused"))
        XCTAssertFalse(AdbOutput.connectSucceeded("cannot connect to 192.168.1.20:5555: Operation timed out"))
        XCTAssertFalse(AdbOutput.connectSucceeded(""))
    }

    func testModelMatches() {
        XCTAssertTrue(AdbOutput.modelMatches(adbModel: "Pixel_7", peerModel: "Pixel 7"))
        XCTAssertTrue(AdbOutput.modelMatches(adbModel: "SM_G991B", peerModel: "SM-G991B"))
        XCTAssertTrue(AdbOutput.modelMatches(adbModel: "pixel_7", peerModel: "PIXEL 7"))
        XCTAssertFalse(AdbOutput.modelMatches(adbModel: "Pixel_8", peerModel: "Pixel 7"))
        XCTAssertFalse(AdbOutput.modelMatches(adbModel: nil, peerModel: "Pixel 7"))
        XCTAssertFalse(AdbOutput.modelMatches(adbModel: "__", peerModel: "--"))
    }
}
