import SefirahCore
import XCTest

final class ScrcpyArgumentsTests: XCTestCase {
    private func settings() -> DeviceSettings {
        var s = DeviceSettings(deviceId: "d")
        s.screenOff = false
        s.scrcpyClipboardAutosync = true
        s.frameRate = 0
        s.display = ""
        return s
    }

    func testDefaultsProduceNoArguments() {
        XCTAssertEqual(ScrcpyArguments.build(settings: settings(), serial: nil), [])
    }

    func testPackageAndAppName() {
        let args = ScrcpyArguments.build(settings: settings(), serial: nil, package: "com.x", appName: "X App")
        XCTAssertEqual(args.prefix(2), ["--start-app=com.x", "--window-title=X App"])
    }

    func testSerial() {
        let args = ScrcpyArguments.build(settings: settings(), serial: "ABC123")
        XCTAssertEqual(args, ["-s", "ABC123"])
    }

    func testFlexDisplayWithPackage() {
        var s = settings()
        s.flexDisplay = true
        s.isVirtualDisplayEnabled = true
        let args = ScrcpyArguments.build(settings: s, serial: nil, package: "com.x")
        XCTAssertTrue(args.contains("--video-bit-rate=16M"))
        XCTAssertTrue(args.contains("--new-display"))
        XCTAssertTrue(args.contains("-x"))
        XCTAssertTrue(args.contains("--keep-active"))
        // Without a package, no virtual display flags.
        let noPkg = ScrcpyArguments.build(settings: s, serial: nil)
        XCTAssertFalse(noPkg.contains("--new-display"))
        XCTAssertFalse(noPkg.contains("--video-bit-rate=16M"))
    }

    func testAudioModes() {
        var s = settings()
        s.audioOutputMode = .remote
        XCTAssertEqual(ScrcpyArguments.build(settings: s, serial: nil), ["--no-audio"])
        s.audioOutputMode = .both
        XCTAssertEqual(ScrcpyArguments.build(settings: s, serial: nil), ["--audio-dup"])
        s.audioOutputMode = .desktop
        XCTAssertEqual(ScrcpyArguments.build(settings: s, serial: nil), [])
    }

    func testCustomArgumentsSplitOnWhitespace() {
        var s = settings()
        s.customArguments = "  --max-size=1024   --stay-awake\t--no-audio "
        XCTAssertEqual(ScrcpyArguments.build(settings: s, serial: nil), ["--max-size=1024", "--stay-awake", "--no-audio"])
    }

    func testDefaultDeviceSettingsFlags() {
        let args = ScrcpyArguments.build(settings: DeviceSettings(deviceId: "d"), serial: nil)
        XCTAssertEqual(args, ["--turn-screen-off", "--no-clipboard-autosync", "--max-fps=60", "--display-id=0"])
    }
}
