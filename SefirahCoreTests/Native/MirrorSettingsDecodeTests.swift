import Foundation
@testable import SefirahCore
import XCTest

final class MirrorSettingsDecodeTests: XCTestCase {
    func testGeneralSettingsWithoutMirrorFieldsUsesDefaults() throws {
        let json = #"{"startupOption":"InTray","theme":"Default","scrcpyPath":"","adbPath":"","remoteStoragePath":"/x","receivedFilesPath":"/y","localDeviceName":"","actions":[]}"#
        let g = try JSONDecoder().decode(GeneralSettings.self, from: Data(json.utf8))
        XCTAssertEqual(g.mirrorBackend, .native)
        XCTAssertFalse(g.verboseMirrorLogs)
        XCTAssertFalse(g.mirrorFallbackToExternal)
    }

    func testGeneralSettingsRoundTripsFallbackFlag() throws {
        var g = GeneralSettings()
        g.mirrorFallbackToExternal = true
        g.mirrorBackend = .external
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(GeneralSettings.self, from: data)
        XCTAssertEqual(back, g)
    }

    func testAudioSettingsMapToServerOptions() throws {
        var s = DeviceSettings(deviceId: "d")
        s.audioOutputMode = .both
        s.audioCodec = 1
        s.audioBitrate = "96K"
        s.audioBuffer = 80
        let o = try ServerOptionsBuilder.build(settings: s, package: nil, scid: 1, av1Supported: false).options
        XCTAssertEqual(o.audioSource, .playback)
        XCTAssertTrue(o.audioDup)
        XCTAssertEqual(o.audioCodec, .aac)
        XCTAssertEqual(o.audioBitRate, 96_000)
        let args = try o.arguments()
        XCTAssertTrue(args.contains("audio_codec=aac"))
        XCTAssertTrue(args.contains("audio_source=playback"))
        XCTAssertTrue(args.contains("audio_dup=true"))
        XCTAssertTrue(args.contains("audio_bit_rate=96000"))

        s.audioOutputMode = .remote
        let off = try ServerOptionsBuilder.build(settings: s, package: nil, scid: 1, av1Supported: false).options
        XCTAssertFalse(off.audio)
        XCTAssertTrue(try off.arguments().contains("audio=false"))
    }
}
