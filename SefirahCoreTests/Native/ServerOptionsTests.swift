import Foundation
@testable import SefirahCore
import XCTest

final class ServerOptionsTests: XCTestCase {
    private func settings(_ mutate: (inout DeviceSettings) -> Void = { _ in }) -> DeviceSettings {
        var s = DeviceSettings(deviceId: "d")
        s.screenOff = false
        s.frameRate = 0
        s.scrcpyClipboardAutosync = true
        mutate(&s)
        return s
    }

    private func build(_ s: DeviceSettings, package: String? = nil, av1: Bool = false) throws -> ServerOptions {
        try ServerOptionsBuilder.build(settings: s, package: package, scid: 0xabcd, av1Supported: av1).options
    }

    func testDefaults() throws {
        XCTAssertEqual(try ServerOptions(scid: 0xabcd).arguments(), ["4.1", "scid=0000abcd", "log_level=info", "tunnel_forward=true"])
        XCTAssertEqual(ServerOptions(scid: 0xabcd).socketName, "scrcpy_0000abcd")
        XCTAssertEqual(ServerOptions(scid: 0xffff_ffff).scid, 0x7fff_ffff)
    }

    func testServerVersionMatchesLockFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let lock = try String(contentsOf: root.appendingPathComponent("scripts/scrcpy.lock"), encoding: .utf8)
        let line = lock.split(whereSeparator: \.isNewline).first { $0.hasPrefix("SCRCPY_VERSION=") }
        XCTAssertEqual(line.map { String($0.dropFirst("SCRCPY_VERSION=".count)) }, ServerOptions.serverVersion)
    }

    func testSettingsMapping() throws {
        let s = settings {
            $0.videoResolution = "1280"
            $0.videoBitrate = "2000K"
            $0.frameRate = 30
            $0.crop = "100:200:0:0"
            $0.display = "2"
            $0.videoCodec = 1
            $0.audioBitrate = "64K"
            $0.audioCodec = 1
            $0.scrcpyClipboardAutosync = false
            $0.rotationAngle = 90
            $0.customArguments = "stay_awake=true --no-audio show_touches=true"
        }
        let result = try ServerOptionsBuilder.build(settings: s, package: nil, scid: 1, av1Supported: false)
        XCTAssertEqual(try result.options.arguments(), [
            "4.1", "scid=00000001", "log_level=info", "tunnel_forward=true",
            "video_codec=h265", "audio_codec=aac", "video_bit_rate=2000000", "audio_bit_rate=64000",
            "max_size=1280", "max_fps=30", "angle=90", "crop=100:200:0:0", "display_id=2",
            "clipboard_autosync=false", "show_touches=true", "stay_awake=true",
        ].sorted(by: { _, _ in false }).reorderedLikeDeclaration())
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("--no-audio"))
    }

    func testAudioModes() throws {
        XCTAssertFalse(try build(settings { $0.audioOutputMode = .remote }).audio)
        let both = try build(settings { $0.audioOutputMode = .both })
        XCTAssertEqual(both.audioSource, .playback)
        XCTAssertTrue(both.audioDup)
        let mic = try build(settings { $0.audioOutputMode = .both; $0.forwardMicrophone = true })
        XCTAssertEqual(mic.audioSource, .mic)
        XCTAssertFalse(mic.audioDup)
        XCTAssertFalse(try build(settings { $0.disableVideoForwarding = true }).video)
        XCTAssertEqual(try build(settings { $0.audioCodec = 2 }).audioCodec, .raw)
    }

    func testVirtualDisplay() throws {
        let plain = try build(settings { $0.display = "3" }, package: "com.x")
        XCTAssertEqual(plain.newDisplay, "")
        XCTAssertEqual(plain.displayId, 0, "display_id must be dropped with new_display")
        XCTAssertFalse(plain.flexDisplay)
        let flex = try build(settings { $0.virtualDisplaySize = "800x600"; $0.flexDisplay = true; $0.videoBitrate = "4M" }, package: "com.x")
        XCTAssertEqual(flex.newDisplay, "800x600")
        XCTAssertTrue(flex.flexDisplay)
        XCTAssertTrue(flex.keepActive)
        XCTAssertEqual(flex.videoBitRate, 16_000_000, "flex forces 16M like ScrcpyArguments")
        XCTAssertEqual(try build(settings { $0.isVirtualDisplayEnabled = false }, package: "com.x").newDisplay, nil)
        XCTAssertThrowsError(try build(settings { $0.flexDisplay = true; $0.crop = "1:1:0:0" }, package: "com.x")) {
            XCTAssertEqual($0 as? ServerOptionsError, .cropWithFlexDisplay)
        }
    }

    func testValidationErrors() {
        XCTAssertThrowsError(try build(settings { $0.videoBitrate = "fast" })) { XCTAssertEqual($0 as? ServerOptionsError, .invalidBitrate("fast")) }
        XCTAssertThrowsError(try build(settings { $0.crop = "1:2:3" })) { XCTAssertEqual($0 as? ServerOptionsError, .invalidCrop("1:2:3")) }
        XCTAssertThrowsError(try build(settings { $0.display = "x" })) { XCTAssertEqual($0 as? ServerOptionsError, .invalidDisplayId("x")) }
        XCTAssertThrowsError(try build(settings { $0.videoCodec = 2 })) { XCTAssertEqual($0 as? ServerOptionsError, .unsupportedCodec("AV1")) }
        XCTAssertEqual(try build(settings { $0.videoCodec = 2 }, av1: true).videoCodec, .av1)
        XCTAssertThrowsError(try build(settings { $0.customArguments = "k=a;rm" })) {
            XCTAssertEqual($0 as? ServerOptionsError, .invalidValue(key: "k", value: "a;rm"))
        }
        for bad in [" ", "'", "\"", "*", "$", "?", "&", "`", "#", "\\", "|", "<", ">", "[", "]", "{", "}", "(", ")", "!", "~", "\r", "\n"] {
            XCTAssertThrowsError(try ServerOptions.validate("a\(bad)b", key: "k"), "\(bad.debugDescription) should be rejected")
        }
        XCTAssertNoThrow(try ServerOptions.validate("800x600/160", key: "new_display"))
        XCTAssertNoThrow(try ServerOptions.validate("", key: "new_display"))
    }

    func testParseBitrate() {
        XCTAssertEqual(ServerOptionsBuilder.parseBitrate("8M"), 8_000_000)
        XCTAssertEqual(ServerOptionsBuilder.parseBitrate("2000k"), 2_000_000)
        XCTAssertEqual(ServerOptionsBuilder.parseBitrate("500000"), 500_000)
        XCTAssertNil(ServerOptionsBuilder.parseBitrate("0"))
        XCTAssertNil(ServerOptionsBuilder.parseBitrate("M"))
        XCTAssertNil(ServerOptionsBuilder.parseBitrate("8G"))
    }

    func testStartupActionsOrder() {
        let s = settings { $0.screenOff = true; $0.physicalKeyboard = true }
        XCTAssertEqual(ServerOptionsBuilder.startupActions(settings: s, package: "com.x"), [.displayPower(on: false), .uhidKeyboard, .startApp("com.x")])
        XCTAssertEqual(ServerOptionsBuilder.startupActions(settings: settings(), package: nil), [])
    }

    func testVerboseLogs() throws {
        let r = try ServerOptionsBuilder.build(settings: settings(), package: nil, scid: 1, av1Supported: false, verboseLogs: true)
        XCTAssertEqual(r.options.logLevel, "debug")
    }
}

private extension Array where Element == String {
    /// The builder emits non-defaults in `ServerOptions` declaration order, then extras sorted by key.
    func reorderedLikeDeclaration() -> [String] {
        let order = ["4.1", "scid=", "log_level=", "tunnel_forward=", "video=", "audio=", "control=", "video_codec=", "audio_codec=",
                     "audio_source=", "audio_dup=", "max_size=", "video_bit_rate=", "audio_bit_rate=", "max_fps=", "angle=", "crop=",
                     "display_id=", "new_display=", "flex_display=", "keep_active=", "clipboard_autosync="]
        func rank(_ s: String) -> Int { order.firstIndex { s.hasPrefix($0) } ?? order.count }
        return sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a < b
        }
    }
}
