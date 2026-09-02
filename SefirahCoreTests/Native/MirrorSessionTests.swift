import Foundation
@testable import SefirahCore
import XCTest

final class MirrorSessionTests: XCTestCase {
    private let adbURL = URL(fileURLWithPath: "/App/Contents/MacOS/adb")
    private let jar = URL(fileURLWithPath: "/App/Contents/Resources/scrcpy/scrcpy-server")
    private let serial = "192.168.0.103:5555"
    private func ok(_ stdout: String = "") -> FakeCommandRunner.Step { .result(CommandResult(exitCode: 0, stdout: stdout, stderr: "")) }

    private struct Harness {
        let runner: FakeCommandRunner
        let spawner: FakeSpawner
        let connector: ScriptedConnector
        let sink: RecordingVideoSink
        let audioSink: RecordingAudioSink
        let log: EventLog
        let session: MirrorSession
    }

    private func harness(options: ServerOptions? = nil, actions: [StartupAction] = [], steps: [FakeCommandRunner.Step]? = nil,
                         unlockCommands: [UnlockCommandEntry] = [], streams: [MemoryByteStream]) -> Harness
    {
        let runner = FakeCommandRunner(steps ?? [ok("pushed"), ok("62990\n"), ok(""), ok(""), ok(""), ok("")])
        let spawner = FakeSpawner()
        let connector = ScriptedConnector(streams)
        let sink = RecordingVideoSink()
        let audioSink = RecordingAudioSink()
        let log = EventLog()
        var timeouts = MirrorSession.Timeouts()
        timeouts.dummyByteRetryDelay = 0.005
        timeouts.dummyByteTotal = 3
        timeouts.exitWait = 0.05
        let launcher = ServerLauncher(adb: AdbClient(adb: adbURL, environment: [:], runner: runner), serverJar: jar, spawner: spawner)
        let config = MirrorSessionConfig(key: "k", serial: serial, options: options ?? ServerOptions(scid: 0xabcd), actions: actions,
                                         unlockCommands: unlockCommands)
        let session = MirrorSession(config: config, launcher: launcher, connector: connector, videoSink: sink, audioSink: audioSink,
                                    timeouts: timeouts) { log.append($0) }
        return Harness(runner: runner, spawner: spawner, connector: connector, sink: sink, audioSink: audioSink, log: log, session: session)
    }

    /// Opus codec id, OpusHead config packet, one media packet.
    private func audioScript() -> Data {
        var d = Fixtures.codecID(0x6f70_7573)
        d.append(Fixtures.packet(pts: 0, config: true, payload: Hex.data("4f70757348656164 01 02 7800 80bb0000 0000 00")))
        d.append(Fixtures.packet(pts: 5000, payload: Hex.data("fcfffe")))
        return d
    }

    func testAudioPacketsReachTheSinkAndTeardownStopsIt() async throws {
        let video = MemoryByteStream(videoScript(), name: "video")
        let audio = MemoryByteStream(audioScript(), name: "audio")
        let control = MemoryByteStream(name: "control")
        let h = harness(streams: [video, audio, control])

        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.audioSink.packets.count >= 1 && h.sink.samples.count >= 2 }
        XCTAssertEqual(h.audioSink.configured.map(\.codec), [.opus])
        XCTAssertEqual(h.audioSink.configured.first?.config?.count, 19)
        XCTAssertEqual(Hex.string(h.audioSink.packets[0]), "fcfffe")
        XCTAssertTrue(h.log.all.contains { if case .audioCodec(.opus) = $0 { return true } else { return false } })
        XCTAssertFalse(h.log.all.contains { if case .audioUnavailable = $0 { return true } else { return false } })

        await h.session.stop()
        await runner.value
        XCTAssertEqual(h.audioSink.stops, 1)
        XCTAssertEqual(h.log.states.last, .idle)
    }

    func testRawAudioConfiguresSinkWithoutConfigPacket() async throws {
        let video = MemoryByteStream(videoScript(), name: "video")
        var script = Fixtures.codecID(0x0072_6177)
        script.append(Fixtures.packet(pts: 1, payload: Data(count: 4096)))
        let audio = MemoryByteStream(script, name: "audio")
        let control = MemoryByteStream(name: "control")
        let h = harness(streams: [video, audio, control])
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.audioSink.packets.count >= 1 }
        XCTAssertEqual(h.audioSink.configured.map(\.codec), [.raw])
        XCTAssertNil(h.audioSink.configured.first?.config)
        XCTAssertEqual(h.audioSink.packets[0].count, 4096)
        await h.session.stop()
        await runner.value
    }

    func testUnsupportedAudioCodecFails() async throws {
        let video = MemoryByteStream(videoScript(), name: "video")
        let audio = MemoryByteStream(Fixtures.codecID(0x666c_6163), name: "audio")
        let control = MemoryByteStream(name: "control")
        let h = harness(streams: [video, audio, control])
        await h.session.start()
        XCTAssertEqual(h.log.states.last, .failed(.unsupportedAudioCodec(0x666c_6163)))
        XCTAssertEqual(h.audioSink.stops, 1)
    }

    func testUnlockCommandsRunBeforePush() async throws {
        var options = ServerOptions(scid: 0xabcd)
        options.audio = false
        let video = MemoryByteStream(videoScript(), name: "video")
        let control = MemoryByteStream(name: "control")
        let steps: [FakeCommandRunner.Step] = [
            ok(""), .result(CommandResult(exitCode: 1, stdout: "", stderr: "nope")),   // unlock commands
            ok("pushed"), ok("62990\n"), ok(""), ok(""), ok(""), ok(""),
        ]
        let h = harness(options: options, steps: steps,
                        unlockCommands: [UnlockCommandEntry(command: "input keyevent 82"), UnlockCommandEntry(command: "wm dismiss-keyguard"),
                                         UnlockCommandEntry(command: "input text %pwd%"), UnlockCommandEntry(command: "  ")],
                        streams: [video, control])
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.sink.samples.count >= 1 }
        await h.session.stop()
        await runner.value

        XCTAssertEqual(h.runner.calls[0], ["-s", serial, "shell", "input keyevent 82"])
        XCTAssertEqual(h.runner.calls[1], ["-s", serial, "shell", "wm dismiss-keyguard"])
        XCTAssertEqual(h.runner.calls[2].prefix(3), ["-s", serial, "push"])
        XCTAssertEqual(h.log.states.prefix(2), [.preparing(.unlock), .preparing(.push)])
        let warnings = h.log.all.compactMap { if case .warning(let w) = $0 { return w } else { return nil } }
        XCTAssertEqual(warnings.count, 2, "\(warnings)")
        XCTAssertTrue(warnings[0].contains("exited 1"))
        XCTAssertTrue(warnings[1].contains("%pwd%"))
    }

    /// dummy byte, 64-byte name, codec id, session packet, config, keyframe, delta frame.
    private func videoScript(codec: UInt32 = 0x6832_3634, config: Data = Fixtures.h264Config) -> Data {
        var d = Data([0])
        d.append(Fixtures.deviceMeta)
        d.append(Fixtures.codecID(codec))
        d.append(Fixtures.session(width: 576, height: 1280))
        d.append(Fixtures.packet(pts: 0, config: true, payload: config))
        d.append(Fixtures.packet(pts: 1000, keyFrame: true, payload: Fixtures.h264KeyFrame))
        d.append(Fixtures.packet(pts: 2000, payload: Hex.data("00000001 41aabbcc")))
        return d
    }

    func testFullHandshakeWithDummyByteRetry() async throws {
        let eof = MemoryByteStream(finished: true, name: "eof")
        let video = MemoryByteStream(videoScript(), name: "video")
        let audio = MemoryByteStream(Fixtures.codecID(0), name: "audio")
        let control = MemoryByteStream(name: "control")
        let h = harness(actions: [.displayPower(on: false), .startApp("com.x")], streams: [eof, video, audio, control])

        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.sink.samples.count >= 2 }
        XCTAssertEqual(h.sink.samples.map(\.keyFrame), [true, false])
        XCTAssertEqual(h.sink.samples.map(\.pts), [1000, 2000])
        XCTAssertEqual(h.sink.formats.map { "\($0.width)x\($0.height)" }, ["576x1280"])
        XCTAssertEqual(h.session.currentVideoSize?.width, 576)
        try await ControlChannelTests.waitUntil { control.written.count >= 9 }
        XCTAssertEqual(Hex.string(control.written), "0a00" + "1005636f6d2e78", "startup actions in order")

        await h.session.stop()
        await h.session.stop() // idempotent
        await runner.value

        XCTAssertEqual(h.log.states, [.preparing(.push), .preparing(.tunnel), .preparing(.spawn), .connecting, .streaming, .stopping, .idle])
        let names = h.log.all.compactMap { if case .deviceName(let n) = $0 { return n } else { return nil } }
        XCTAssertEqual(names, ["24031PN0DC"])
        XCTAssertTrue(h.log.all.contains { if case .audioUnavailable = $0 { return true } else { return false } })
        XCTAssertTrue(h.log.all.contains { if case .videoSize(576, 1280, false) = $0 { return true } else { return false } })
        XCTAssertTrue(h.log.all.contains { if case .videoCodec(.h264) = $0 { return true } else { return false } })

        XCTAssertEqual(h.connector.connects.map(\.port), [62990, 62990, 62990, 62990])
        XCTAssertEqual(h.connector.connects.map(\.noDelay), [false, false, false, true])
        XCTAssertTrue(eof.isClosed)
        XCTAssertTrue(video.isClosed && audio.isClosed && control.isClosed)
        XCTAssertEqual(h.runner.calls[0], ["-s", serial, "push", jar.path, "/data/local/tmp/scrcpy-server.jar"])
        XCTAssertEqual(h.runner.calls[1], ["-s", serial, "forward", "tcp:0", "localabstract:scrcpy_0000abcd"])
        XCTAssertEqual(h.runner.calls[2], ["-s", serial, "forward", "--remove", "tcp:62990"], "forward removed once sockets are up")
        XCTAssertTrue(h.runner.calls.contains(["-s", serial, "shell", "pkill", "-f", "scid=0000abcd"]), "\(h.runner.calls)")
        XCTAssertEqual(h.spawner.spawned[0].arguments.prefix(7), ["-s", serial, "shell", "CLASSPATH=/data/local/tmp/scrcpy-server.jar", "app_process", "/", "com.genymobile.scrcpy.Server"])
        XCTAssertGreaterThanOrEqual(h.sink.flushes, 1)
        XCTAssertTrue(h.spawner.last?.terminated ?? false, "adb shell terminated when it does not exit by itself")
    }

    func testHEVCHandshake() async throws {
        let video = MemoryByteStream(videoScript(codec: 0x6832_3635, config: Fixtures.h265Config), name: "video")
        var options = ServerOptions(scid: 1)
        options.audio = false
        options.control = false
        let h = harness(options: options, streams: [video])
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.sink.samples.count >= 1 }
        XCTAssertEqual(h.sink.formats.first.map { "\($0.width)x\($0.height)" }, "576x1280")
        await h.session.stop()
        await runner.value
        XCTAssertEqual(h.connector.connects.count, 1)
        XCTAssertEqual(h.log.states.last, .idle)
    }

    /// A sink drop (renderer not draining) must gate delta frames until the next keyframe and
    /// request one via `resetVideo` instead of feeding P-frames with a missing reference.
    func testSinkDropRequestsKeyframeAndGatesDeltaFrames() async throws {
        var script = Data([0])
        script.append(Fixtures.deviceMeta)
        script.append(Fixtures.codecID(0x6832_3634))
        script.append(Fixtures.session(width: 576, height: 1280))
        script.append(Fixtures.packet(pts: 0, config: true, payload: Fixtures.h264Config))
        script.append(Fixtures.packet(pts: 10, keyFrame: true, payload: Fixtures.h264KeyFrame))
        script.append(Fixtures.packet(pts: 20, payload: Hex.data("00000001 41aa")))   // dropped by the sink
        script.append(Fixtures.packet(pts: 30, payload: Hex.data("00000001 41bb")))   // must be gated
        script.append(Fixtures.packet(pts: 40, keyFrame: true, payload: Fixtures.h264KeyFrame))
        script.append(Fixtures.packet(pts: 50, payload: Hex.data("00000001 41cc")))
        var options = ServerOptions(scid: 1)
        options.audio = false
        let control = MemoryByteStream(name: "control")
        let h = harness(options: options, streams: [MemoryByteStream(script), control])
        h.sink.dropNextInterFrames = 1
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.sink.samples.count >= 3 }
        XCTAssertEqual(h.sink.samples.map(\.pts), [10, 40, 50])
        XCTAssertEqual(h.sink.dropped, 1)
        try await ControlChannelTests.waitUntil { control.written.contains(0x11) }
        XCTAssertEqual(control.written.filter { $0 == 0x11 }.count, 1, "one rate-limited resetVideo")
        await h.session.stop()
        await runner.value
    }

    func testKeyframeGatingDropsDeltaFramesUntilKeyframe() async throws {
        var script = Data([0])
        script.append(Fixtures.deviceMeta)
        script.append(Fixtures.codecID(0x6832_3634))
        script.append(Fixtures.session(width: 576, height: 1280))
        script.append(Fixtures.packet(pts: 0, config: true, payload: Fixtures.h264Config))
        script.append(Fixtures.packet(pts: 10, payload: Hex.data("00000001 41aa")))
        script.append(Fixtures.packet(pts: 20, payload: Hex.data("00000001 41bb")))
        script.append(Fixtures.packet(pts: 30, keyFrame: true, payload: Fixtures.h264KeyFrame))
        script.append(Fixtures.packet(pts: 40, payload: Hex.data("00000001 41cc")))
        // Rotation: new session packet + config → next delta must be dropped again.
        script.append(Fixtures.session(width: 1280, height: 576))
        script.append(Fixtures.packet(pts: 0, config: true, payload: Fixtures.h264Config))
        script.append(Fixtures.packet(pts: 50, payload: Hex.data("00000001 41dd")))
        script.append(Fixtures.packet(pts: 60, keyFrame: true, payload: Fixtures.h264KeyFrame))
        var options = ServerOptions(scid: 1)
        options.audio = false
        options.control = false
        let h = harness(options: options, streams: [MemoryByteStream(script)])
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.sink.samples.count >= 3 }
        XCTAssertEqual(h.sink.samples.map(\.pts), [30, 40, 60])
        XCTAssertEqual(h.session.currentVideoSize?.width, 1280)
        XCTAssertEqual(h.sink.formats.count, 2)
        let sizes = h.log.all.compactMap { if case .videoSize(let w, let h, _) = $0 { return "\(w)x\(h)" } else { return nil } }
        XCTAssertEqual(sizes, ["576x1280", "1280x576"])
        await h.session.stop()
        await runner.value
    }

    func testServerExitDuringHandshake() async throws {
        let eofs = (0..<50).map { _ in MemoryByteStream(finished: true) }
        let h = harness(streams: eofs)
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.spawner.last != nil && h.connector.connects.count >= 2 }
        h.spawner.last!.emit("[server] ERROR: Exception on thread Thread[main]")
        h.spawner.last!.exit(1)
        await runner.value
        guard case .failed(.serverExited(let code, let log)) = h.log.states.last! else { return XCTFail("\(h.log.states)") }
        XCTAssertEqual(code, 1)
        XCTAssertTrue(log.contains("Exception on thread"))
        XCTAssertTrue(h.runner.calls.contains(["-s", serial, "shell", "pkill", "-f", "scid=0000abcd"]))
        let serverLogs = h.log.all.compactMap { if case .serverLog(let l) = $0 { return l } else { return nil } }
        XCTAssertEqual(serverLogs, ["[server] ERROR: Exception on thread Thread[main]"])
    }

    func testVersionMismatch() async throws {
        let h = harness(streams: (0..<50).map { _ in MemoryByteStream(finished: true) })
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.spawner.last != nil }
        let line = "[server] ERROR: The server version (4.1) does not match the client (4.0)"
        h.spawner.last!.emit(line)
        h.spawner.last!.exit(1)
        await runner.value
        XCTAssertEqual(h.log.states.last, .failed(.versionMismatch(line)))
    }

    func testPushFailure() async {
        let h = harness(steps: [.result(CommandResult(exitCode: 1, stdout: "", stderr: "error: device offline")), ok(""), ok("")], streams: [])
        await h.session.start()
        XCTAssertEqual(h.log.states.last, .failed(.adb(.commandFailed(command: "-s \(serial) push", exitCode: 1, stderr: "error: device offline"))))
        XCTAssertTrue(h.runner.calls.contains(["-s", serial, "shell", "pkill", "-f", "scid=0000abcd"]), "killServer runs on every teardown")
    }

    func testVideoDisabledReadsNameFromAudioStream() async throws {
        var script = Data([0])
        script.append(Fixtures.deviceMeta)
        script.append(Fixtures.codecID(0x6f70_7573))
        script.append(Fixtures.packet(pts: 0, config: true, payload: Data("OpusHead".utf8)))
        script.append(Fixtures.packet(pts: 5, payload: Hex.data("fcfffe")))
        var options = ServerOptions(scid: 1)
        options.video = false
        let audio = MemoryByteStream(script, name: "audio")
        let control = MemoryByteStream(name: "control")
        let h = harness(options: options, streams: [audio, control])
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.log.states.contains(.streaming) }
        let names = h.log.all.compactMap { if case .deviceName(let n) = $0 { return n } else { return nil } }
        XCTAssertEqual(names, ["24031PN0DC"])
        XCTAssertEqual(h.connector.connects.map(\.noDelay), [true, true], "first socket is audio; control gets TCP_NODELAY")
        await h.session.stop()
        await runner.value
        XCTAssertEqual(h.log.states.last, .idle)
    }

    func testConnectionLostAfterStreaming() async throws {
        let video = MemoryByteStream(videoScript(), name: "video")
        var options = ServerOptions(scid: 1)
        options.audio = false
        options.control = false
        let h = harness(options: options, streams: [video])
        let runner = Task { await h.session.start() }
        try await ControlChannelTests.waitUntil { h.sink.samples.count >= 2 }
        video.finish()
        await runner.value
        XCTAssertEqual(h.log.states.last, .failed(.connectionLost))
    }

    func testUnsupportedVideoCodec() async throws {
        var script = Data([0])
        script.append(Fixtures.deviceMeta)
        script.append(Fixtures.codecID(0x0076_7038))
        var options = ServerOptions(scid: 1)
        options.audio = false
        options.control = false
        let h = harness(options: options, streams: [MemoryByteStream(script)])
        await h.session.start()
        XCTAssertEqual(h.log.states.last, .failed(.unsupportedVideoCodec(0x0076_7038)))
    }

    func testFirstPacketMustBeSession() async throws {
        var script = Data([0])
        script.append(Fixtures.deviceMeta)
        script.append(Fixtures.codecID(0x6832_3634))
        script.append(Fixtures.packet(pts: 0, config: true, payload: Fixtures.h264Config))
        var options = ServerOptions(scid: 1)
        options.audio = false
        options.control = false
        let h = harness(options: options, streams: [MemoryByteStream(script)])
        await h.session.start()
        guard case .failed(.protocolError) = h.log.states.last! else { return XCTFail("\(h.log.states)") }
    }

    func testNativeToolsLocate() {
        let tools = NativeTools.locate(
            auxiliaryExecutable: { URL(fileURLWithPath: "/App/Contents/MacOS/\($0)") },
            resourcesRoot: URL(fileURLWithPath: "/App/Contents/Resources"),
            exists: { !$0.path.hasSuffix("/scrcpy") },
            readVersion: { _ in "4.1\n" }
        )
        XCTAssertEqual(tools?.adb.path, "/App/Contents/MacOS/adb")
        XCTAssertEqual(tools?.server.path, "/App/Contents/Resources/scrcpy/scrcpy-server")
        XCTAssertEqual(tools?.version, "4.1")
        XCTAssertNil(NativeTools.locate(auxiliaryExecutable: { _ in nil }, resourcesRoot: nil, exists: { _ in true }, readVersion: { _ in nil }))
    }
}
