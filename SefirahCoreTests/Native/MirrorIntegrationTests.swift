import CoreMedia
import Foundation
@testable import SefirahCore
import XCTest

/// Real-device run; skipped unless `SEFIRAH_TEST_ADB_SERIAL` is set. Never sends input.
/// Env: `SEFIRAH_TEST_ADB` (adb path), `SEFIRAH_TEST_SCRCPY_SERVER` (jar path), `SEFIRAH_TEST_VIDEO_CODEC` (h264|h265).
///
/// `xcodebuild test` does not forward plain shell env vars to the xctest host; prefix them with
/// `TEST_RUNNER_` (xcodebuild strips the prefix), e.g.
/// `TEST_RUNNER_SEFIRAH_TEST_ADB_SERIAL=192.168.0.103:5555 xcodebuild ... test -only-testing:SefirahCoreTests/MirrorIntegrationTests`.
/// Alternatively set the variables in the scheme's Test action.
final class MirrorIntegrationTests: XCTestCase {
    private var adb: AdbClient!
    private var serial: String!
    private var serverJar: URL!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let serial = env["SEFIRAH_TEST_ADB_SERIAL"] else {
            throw XCTSkip("Set SEFIRAH_TEST_ADB_SERIAL to run against a real device")
        }
        self.serial = serial
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let adbPath = env["SEFIRAH_TEST_ADB"] ?? root.appendingPathComponent("Vendor/scrcpy/adb").path
        let jarPath = env["SEFIRAH_TEST_SCRCPY_SERVER"] ?? root.appendingPathComponent("Vendor/scrcpy/scrcpy-server").path
        var shellEnv = env
        if shellEnv["HOME"] == nil { shellEnv["HOME"] = NSHomeDirectory() }
        if shellEnv["PATH"] == nil { shellEnv["PATH"] = ScrcpyLaunchPlanner.defaultPath }
        adb = AdbClient(adb: URL(fileURLWithPath: adbPath), environment: shellEnv)
        serverJar = URL(fileURLWithPath: jarPath)
    }

    func testVideoHandshakeAndTeardown() async throws {
        let codecName = ProcessInfo.processInfo.environment["SEFIRAH_TEST_VIDEO_CODEC"] ?? "h264"
        var options = ServerOptions(scid: 0x1234_abcd)
        options.maxSize = 1280
        options.videoCodec = codecName == "h265" ? .h265 : .h264
        let config = MirrorSessionConfig(key: "it", serial: serial, options: options)
        let launcher = ServerLauncher(adb: adb, serverJar: serverJar)

        let log = EventLog()
        let sink = RecordingVideoSink()
        let gotFrames = expectation(description: "5 samples")
        gotFrames.assertForOverFulfill = false
        let counter = Counter()
        sink.onSample = { if counter.increment() == 5 { gotFrames.fulfill() } }

        let capture = ConfigCapture()
        // Real audio pipeline: Opus → AVAudioConverter → AVAudioEngine (verifies decode + engine on this Mac).
        let audio = AudioPlayer(targetLatencyMs: 50)
        let audioErrors = Errors()
        audio.onError = { audioErrors.append($0) }
        let gotAudio = expectation(description: "20 audio packets")
        gotAudio.assertForOverFulfill = false
        let audioSink = CountingAudioSink(audio) { n in if n == 20 { gotAudio.fulfill() } }
        let session = MirrorSession(config: config, launcher: launcher, videoSink: CapturingSink(sink, capture), audioSink: audioSink) { event in
            log.append(event)
            if case .serverLog(let line) = event { print("[server-log] \(line)") }
        }
        let runner = Task { await session.start() }
        await fulfillment(of: [gotFrames, gotAudio], timeout: 30)
        let audioStats = audio.statistics
        print("[it] audio stats: \(audioStats) errors: \(audioErrors.all)")
        await session.stop()
        await runner.value

        let audioCodecs = log.all.compactMap { if case .audioCodec(let c) = $0 { return c } else { return nil } }
        XCTAssertEqual(audioCodecs, [.opus])
        XCTAssertEqual(audioStats.codec, .opus)
        XCTAssertGreaterThanOrEqual(audioStats.packets, 20)
        XCTAssertGreaterThan(audioStats.decodedFrames, 0)
        XCTAssertEqual(audioStats.decodeErrors, 0)
        XCTAssertTrue(audioStats.engineRunning, "AVAudioEngine should be running while streaming")
        XCTAssertTrue(audioErrors.all.isEmpty, "\(audioErrors.all)")
        XCTAssertFalse(audio.statistics.engineRunning, "engine stopped on teardown")

        let states = log.states
        XCTAssertEqual(states.last, .idle, "\(states)")
        XCTAssertTrue(states.contains(.streaming), "\(states)")
        let names = log.all.compactMap { if case .deviceName(let n) = $0 { return n } else { return nil } }
        XCTAssertFalse(names.isEmpty)
        print("[it] device name: \(names)")
        let sizes = log.all.compactMap { if case .videoSize(let w, let h, _) = $0 { return (w, h) } else { return nil } }
        XCTAssertFalse(sizes.isEmpty)
        print("[it] video sizes: \(sizes)")
        XCTAssertGreaterThanOrEqual(sink.samples.count, 5)
        XCTAssertTrue(sink.samples.first?.keyFrame ?? false, "first sample must be a keyframe")
        XCTAssertFalse(sink.formats.isEmpty)
        print("[it] formats: \(sink.formats) samples: \(sink.samples.prefix(6))")
        print("[it] CONFIG_HEX \(codecName) \(Hex.string(capture.config))")
        print("[it] KEYFRAME_HEX \(codecName) \(Hex.string(capture.firstKeyFrame.prefix(512)))")

        // Phone hygiene.
        let pgrep = try await adb.shell(serial: serial, ["pgrep", "-f", "scrcpy"])
        XCTAssertTrue(pgrep.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "server still running: \(pgrep.stdout)")
        let forwards = try await adb.runner.run(adb.adb, ["-s", serial, "forward", "--list"], environment: adb.environment, timeout: 5)
        XCTAssertFalse(forwards.stdout.contains("scrcpy_"), forwards.stdout)
    }

    /// Opt-in: `SEFIRAH_TEST_START_APP=<package>` launches that app on a new virtual display and checks the server log.
    func testVirtualDisplayStartApp() async throws {
        guard let package = ProcessInfo.processInfo.environment["SEFIRAH_TEST_START_APP"], !package.isEmpty else {
            throw XCTSkip("Set SEFIRAH_TEST_START_APP=<package> to run the virtual-display launch")
        }
        var options = ServerOptions(scid: 0x1234_abce)
        options.maxSize = 1024
        options.newDisplay = ""
        options.audio = false
        let config = MirrorSessionConfig(key: "it-app", serial: serial, options: options, actions: [.startApp(package)])
        let launcher = ServerLauncher(adb: adb, serverJar: serverJar)
        let log = EventLog()
        let sink = RecordingVideoSink()
        let gotFrames = expectation(description: "10 samples")
        gotFrames.assertForOverFulfill = false
        let counter = Counter()
        sink.onSample = { if counter.increment() == 10 { gotFrames.fulfill() } }
        let session = MirrorSession(config: config, launcher: launcher, videoSink: sink) { event in
            log.append(event)
            if case .serverLog(let line) = event { print("[server-log] \(line)") }
        }
        let runner = Task { await session.start() }
        await fulfillment(of: [gotFrames], timeout: 30)
        try await Task.sleep(nanoseconds: 2_000_000_000)   // let the START_APP land in the log
        await session.stop()
        await runner.value
        XCTAssertEqual(log.states.last, .idle)
        XCTAssertTrue(log.serverLogs.contains { $0.contains("New display") }, "\(log.serverLogs)")
        XCTAssertFalse(log.serverLogs.contains { $0.contains("ERROR") }, "\(log.serverLogs)")
        let pgrep = try await adb.shell(serial: serial, ["pgrep", "-f", "scrcpy"])
        XCTAssertTrue(pgrep.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "server still running: \(pgrep.stdout)")
    }

    private final class Errors: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        var all: [String] { lock.withLock { items } }
        func append(_ s: String) { lock.withLock { items.append(s) } }
    }

    private final class CountingAudioSink: AudioSink, @unchecked Sendable {
        let inner: AudioPlayer
        let onCount: @Sendable (Int) -> Void
        private let lock = NSLock()
        private var n = 0
        init(_ inner: AudioPlayer, onCount: @escaping @Sendable (Int) -> Void) { self.inner = inner; self.onCount = onCount }
        func configure(codec: StreamCodecID, config: Data?) { inner.configure(codec: codec, config: config) }
        func enqueue(packet: Data) {
            inner.enqueue(packet: packet)
            let c: Int = lock.withLock { n += 1; return n }
            onCount(c)
        }
        func stop() { inner.stop() }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int { lock.withLock { n += 1; return n } }
    }

    private final class ConfigCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var _config = Data()
        private var _key = Data()
        var config: Data { lock.withLock { _config } }
        var firstKeyFrame: Data { lock.withLock { _key } }
        func set(config: Data) { lock.withLock { _config = config } }
        func set(key: Data) { lock.withLock { if _key.isEmpty { _key = key } } }
    }

    /// Wraps the recording sink and additionally captures raw bytes via the format description / sample data.
    private final class CapturingSink: VideoFrameSink, @unchecked Sendable {
        let inner: RecordingVideoSink
        let capture: ConfigCapture
        init(_ inner: RecordingVideoSink, _ capture: ConfigCapture) { self.inner = inner; self.capture = capture }

        func formatChanged(_ format: CMFormatDescription, width: Int, height: Int) {
            // Rebuild Annex-B config from the parameter sets stored in the format description.
            var annexB = Data()
            let hevc = CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC
            var count = 0
            if hevc {
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            } else {
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            }
            for i in 0..<count {
                var p: UnsafePointer<UInt8>?
                var size = 0
                if hevc {
                    CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                } else {
                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                }
                if let p { annexB.append(contentsOf: [0, 0, 0, 1]); annexB.append(Data(bytes: p, count: size)) }
            }
            capture.set(config: annexB)
            inner.formatChanged(format, width: width, height: height)
        }

        @discardableResult
        func enqueue(_ sample: CMSampleBuffer, keyFrame: Bool) -> Bool {
            if keyFrame, let block = CMSampleBufferGetDataBuffer(sample) {
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr, let pointer {
                    capture.set(key: Data(bytes: pointer, count: length))
                }
            }
            return inner.enqueue(sample, keyFrame: keyFrame)
        }

        var requiresFlush: Bool { inner.requiresFlush }
        var failure: String? { inner.failure }
        func flush() { inner.flush() }
    }
}
