import CoreMedia
import Foundation
@testable import SefirahCore
import XCTest

/// Real-device control-socket run; skipped unless `SEFIRAH_TEST_ADB_SERIAL` is set.
/// Exercises only messages that do not depend on INJECT_EVENTS being permitted (clipboard set/get round-trip,
/// display power) and verifies that injection messages are accepted by the socket without breaking the stream.
/// Never rotates the device or changes persistent settings.
final class MirrorControlIntegrationTests: XCTestCase {
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

    func testControlRoundTrips() async throws {
        var options = ServerOptions(scid: 0x2345_bcde)
        options.maxSize = 1280
        options.audio = false
        if let level = ProcessInfo.processInfo.environment["SEFIRAH_TEST_LOG_LEVEL"] { options.logLevel = level }
        options.clipboardAutosync = false // GET_CLIPBOARD only answers when autosync is off (Controller.getClipboard)
        let config = MirrorSessionConfig(key: "ctl", serial: serial, options: options)
        let launcher = ServerLauncher(adb: adb, serverJar: serverJar)

        let log = EventLog()
        let sink = RecordingVideoSink()
        let counter = Counter()
        let firstFrames = expectation(description: "3 samples")
        firstFrames.assertForOverFulfill = false
        sink.onSample = { if counter.increment() == 3 { firstFrames.fulfill() } }

        let session = MirrorSession(config: config, launcher: launcher, videoSink: sink) { event in
            log.append(event)
            if case .serverLog(let line) = event { print("[server-log] \(line)") }
        }
        let runner = Task { await session.start() }
        await fulfillment(of: [firstFrames], timeout: 30)
        XCTAssertTrue(log.states.contains(.streaming))
        XCTAssertNotNil(session.currentVideoSize)
        let size = session.currentVideoSize ?? (width: 0, height: 0)

        // 1. SET_CLIPBOARD → ACK_CLIPBOARD(sequence) proves both directions of the control socket.
        let marker = "sefirah-ctl-\(UInt32.random(in: 0...0xffff_ffff))"
        session.control.send(.setClipboard(sequence: 7, paste: false, text: marker))
        try await waitFor("clipboard ack", timeout: 5) {
            log.all.contains { if case .clipboardAck(7) = $0 { return true } else { return false } }
        }

        // 2. GET_CLIPBOARD(none) → CLIPBOARD(text) with what we just set. Some ROMs (HyperOS on the Xiaomi 14 Ultra)
        //    return null from ClipboardManager.getPrimaryClip for the shell uid, so the reply is only required when
        //    SEFIRAH_TEST_STRICT_CLIPBOARD is set; the message is still sent and must not disturb the socket.
        session.control.send(.getClipboard(.none))
        let gotClipboard = await poll(timeout: 3) {
            log.all.contains { if case .clipboard(let t) = $0 { return t == marker } else { return false } }
        }
        print("[ctl] GET_CLIPBOARD reply received: \(gotClipboard)")
        if ProcessInfo.processInfo.environment["SEFIRAH_TEST_STRICT_CLIPBOARD"] != nil {
            XCTAssertTrue(gotClipboard, "device did not answer GET_CLIPBOARD")
        }

        // 3. SET_DISPLAY_POWER off/on (not subject to INJECT_EVENTS). The server logs "Device display turned off/on"
        //    only when SurfaceControl/DisplayControl accepted the change (Controller.setDisplayPower); on Android 15+
        //    `dumpsys display mScreenState` does not reflect the low-level power mode, so it is printed for information only.
        let before = try await screenState()
        session.control.send(.setDisplayPower(on: false))
        try await waitFor("display off log", timeout: 5) { log.serverLogs.contains { $0.contains("Device display turned off") } }
        let off = try await screenState()
        session.control.send(.setDisplayPower(on: true))
        try await waitFor("display on log", timeout: 5) { log.serverLogs.contains { $0.contains("Device display turned on") } }
        let on = try await screenState()
        print("[ctl] screen state before=\(before) afterOff=\(off) afterOn=\(on)")

        // 4. Injection messages must be accepted by the socket even when the device denies injection.
        let w = UInt16(size.width), h = UInt16(size.height)
        session.control.send(.injectTouch(action: .down, pointerId: AndroidInput.pointerMouse, x: 10, y: 10, screenWidth: w, screenHeight: h,
                                          pressure: 1, actionButton: .primary, buttons: .primary))
        session.control.send(.injectTouch(action: .up, pointerId: AndroidInput.pointerMouse, x: 10, y: 10, screenWidth: w, screenHeight: h,
                                          pressure: 0, actionButton: .primary, buttons: []))
        session.control.send(.injectScroll(x: 10, y: 10, screenWidth: w, screenHeight: h, hscroll: 0, vscroll: 1, buttons: []))
        session.control.send(.injectKeycode(action: .down, keycode: AndroidInput.Keycode.back, repeat: 0, metaState: []))
        session.control.send(.injectKeycode(action: .up, keycode: AndroidInput.Keycode.back, repeat: 0, metaState: []))
        session.control.send(.injectText("sefirah"))
        session.control.send(.backOrScreenOn(.down))
        session.control.send(.backOrScreenOn(.up))
        session.control.send(.collapsePanels)
        session.control.send(.resetVideo)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await waitFor("pending queue drained", timeout: 5) { session.control.pending.isEmpty }
        XCTAssertEqual(session.control.dropped, 0)
        XCTAssertEqual(log.states.last, .streaming, "\(log.states)")

        // Video keeps flowing after the control burst (RESET_VIDEO forces a new keyframe).
        let frameCount = sink.samples.count
        try await waitFor("frames after control burst", timeout: 10) { sink.samples.count > frameCount + 2 }

        await session.stop()
        await runner.value
        XCTAssertEqual(log.states.last, .idle, "\(log.states)")

        // Phone hygiene.
        let pgrep = try await adb.shell(serial: serial, ["pgrep", "-f", "scrcpy"])
        XCTAssertTrue(pgrep.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "server still running: \(pgrep.stdout)")
        let forwards = try await adb.runner.run(adb.adb, ["-s", serial, "forward", "--list"], environment: adb.environment, timeout: 5)
        XCTAssertFalse(forwards.stdout.contains("scrcpy_"), forwards.stdout)
    }

    private func screenState() async throws -> String {
        let r = try await adb.shell(serial: serial, ["dumpsys", "display", "|", "grep", "-m1", "mScreenState"])
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func poll(timeout: TimeInterval, _ condition: @escaping @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func waitFor(_ what: String, timeout: TimeInterval, _ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out waiting for \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() -> Int { lock.withLock { n += 1; return n } }
    }
}
