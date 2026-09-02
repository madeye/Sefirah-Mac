import Foundation
@testable import SefirahCore
import XCTest

final class ServerLauncherTests: XCTestCase {
    private let adbURL = URL(fileURLWithPath: "/App/Contents/MacOS/adb")
    private let jar = URL(fileURLWithPath: "/App/Contents/Resources/scrcpy/scrcpy-server")
    private func ok(_ stdout: String = "") -> FakeCommandRunner.Step { .result(CommandResult(exitCode: 0, stdout: stdout, stderr: "")) }
    private func fail(_ msg: String) -> FakeCommandRunner.Step { .result(CommandResult(exitCode: 1, stdout: "", stderr: msg)) }

    private func launcher(_ runner: FakeCommandRunner, spawner: FakeSpawner = FakeSpawner()) -> ServerLauncher {
        ServerLauncher(adb: AdbClient(adb: adbURL, environment: ["PATH": "/usr/bin"], runner: runner), serverJar: jar, spawner: spawner)
    }

    func testPushArgv() async throws {
        let runner = FakeCommandRunner([ok("1 file pushed")])
        try await launcher(runner).push(serial: "S")
        XCTAssertEqual(runner.calls, [["-s", "S", "push", jar.path, "/data/local/tmp/scrcpy-server.jar"]])
    }

    func testPushFailure() async {
        let runner = FakeCommandRunner([fail("adb: error: failed to copy")])
        do {
            try await launcher(runner).push(serial: "S")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AdbError, .commandFailed(command: "-s S push", exitCode: 1, stderr: "adb: error: failed to copy"))
        }
    }

    func testForwardParsesPort() async throws {
        let runner = FakeCommandRunner([ok("62990\n")])
        let port = try await launcher(runner).forward(serial: "S", socketName: "scrcpy_0000abcd")
        XCTAssertEqual(port, 62990)
        XCTAssertEqual(runner.calls, [["-s", "S", "forward", "tcp:0", "localabstract:scrcpy_0000abcd"]])
        XCTAssertEqual(AdbOutput.parseForwardPort("* daemon started\n1234\n"), 1234)
        XCTAssertNil(AdbOutput.parseForwardPort(""))
    }

    func testForwardWithoutPortFails() async {
        let runner = FakeCommandRunner([ok("")])
        do {
            _ = try await launcher(runner).forward(serial: "S", socketName: "x")
            XCTFail("expected throw")
        } catch {
            XCTAssertNotNil(error as? AdbError)
        }
    }

    func testSpawnArgvExact() throws {
        let spawner = FakeSpawner()
        var options = ServerOptions(scid: 0xabcd)
        options.maxSize = 1280
        let process = try launcher(FakeCommandRunner([]), spawner: spawner).spawn(serial: "192.168.0.103:5555", options: options) { _ in }
        XCTAssertTrue(process.isRunning)
        XCTAssertEqual(spawner.spawned.count, 1)
        XCTAssertEqual(spawner.spawned[0].executable, adbURL)
        XCTAssertEqual(spawner.spawned[0].arguments, [
            "-s", "192.168.0.103:5555", "shell", "CLASSPATH=/data/local/tmp/scrcpy-server.jar", "app_process", "/",
            "com.genymobile.scrcpy.Server", "4.1", "scid=0000abcd", "log_level=info", "tunnel_forward=true", "max_size=1280",
        ])
    }

    func testKillServerAndRemoveForwardArgv() async {
        let runner = FakeCommandRunner([ok(""), ok("")])
        let l = launcher(runner)
        await l.killServer(serial: "S", scid: 0xabcd)
        await l.removeForward(serial: "S", port: 62990)
        XCTAssertEqual(runner.calls, [
            ["-s", "S", "shell", "pkill", "-f", "scid=0000abcd"],
            ["-s", "S", "forward", "--remove", "tcp:62990"],
        ])
    }

    func testKillServerIsBestEffort() async {
        let runner = FakeCommandRunner([.timeout])
        await launcher(runner).killServer(serial: "S", scid: 1)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testProcessServerProcessLinesAndTail() async throws {
        let lines = LineBox()
        let process = try ProcessDetachedSpawner().spawn(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "printf '[server] INFO: a\\n[server] ERROR: b\\n'; printf 'partial' 1>&2; exit 3"],
            environment: ["PATH": "/usr/bin:/bin"]
        ) { lines.append($0) }
        let status = await process.waitForExit(timeout: 5)
        XCTAssertEqual(status, 3)
        XCTAssertFalse(process.isRunning)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(Set(lines.all), ["[server] INFO: a", "[server] ERROR: b", "partial"])
        XCTAssertTrue(process.logTail.contains("[server] ERROR: b"))
    }

    private final class LineBox: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ s: String) { lock.withLock { lines.append(s) } }
        var all: [String] { lock.withLock { lines } }
    }
}
