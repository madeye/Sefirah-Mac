import SefirahCore
import XCTest

final class ScrcpyDeviceSelectionTests: XCTestCase {
    private let usb = AdbDevice(serial: "USB1", state: "device", model: "Pixel_7")
    private let tcp = AdbDevice(serial: "10.0.0.2:5555", state: "device", model: "Pixel_7")
    private let other = AdbDevice(serial: "EMU", state: "device", model: "sdk_gphone64_arm64")

    func testSingleDeviceIsNil() {
        XCTAssertNil(ScrcpyDeviceSelection.serial(devices: [usb], peerModel: "Pixel 7", preference: .auto))
        XCTAssertNil(ScrcpyDeviceSelection.serial(devices: [], peerModel: "Pixel 7", preference: .auto))
        // Offline/unauthorized devices don't count.
        let unauth = AdbDevice(serial: "X", state: "unauthorized", model: nil)
        XCTAssertNil(ScrcpyDeviceSelection.serial(devices: [usb, unauth], peerModel: "Pixel 7", preference: .auto))
    }

    func testPreferenceSelectsAmongMatches() {
        let all = [usb, tcp, other]
        XCTAssertEqual(ScrcpyDeviceSelection.serial(devices: all, peerModel: "Pixel 7", preference: .usb), "USB1")
        XCTAssertEqual(ScrcpyDeviceSelection.serial(devices: all, peerModel: "Pixel 7", preference: .tcpip), "10.0.0.2:5555")
        XCTAssertEqual(ScrcpyDeviceSelection.serial(devices: all, peerModel: "Pixel 7", preference: .auto), "10.0.0.2:5555")
        XCTAssertEqual(ScrcpyDeviceSelection.serial(devices: all, peerModel: "Pixel 7", preference: .askEverytime), "10.0.0.2:5555")
        // Only USB available: tcpip preference falls back to USB.
        XCTAssertEqual(ScrcpyDeviceSelection.serial(devices: [usb, other], peerModel: "Pixel 7", preference: .tcpip), "USB1")
        XCTAssertEqual(ScrcpyDeviceSelection.serial(devices: [usb, other], peerModel: "Pixel 7", preference: .auto), "USB1")
    }

    func testNoMatchIsNil() {
        XCTAssertNil(ScrcpyDeviceSelection.serial(devices: [usb, other], peerModel: "Galaxy S21", preference: .auto))
    }
}
