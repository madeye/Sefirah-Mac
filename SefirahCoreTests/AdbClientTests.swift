import SefirahCore
import XCTest

final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    enum Step { case result(CommandResult), spawnError, timeout }
    private let lock = NSLock()
    private var steps: [Step]
    private(set) var calls: [[String]] = []

    init(_ steps: [Step]) { self.steps = steps }

    private func next(_ arguments: [String]) -> Step {
        lock.withLock {
            calls.append(arguments)
            return steps.isEmpty ? Step.result(CommandResult(exitCode: 1, stdout: "", stderr: "unexpected call")) : steps.removeFirst()
        }
    }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult {
        switch next(arguments) {
        case .result(let r): return r
        case .spawnError: throw AdbError.spawnFailed("ENOENT")
        case .timeout: throw AdbError.timeout(command: arguments.joined(separator: " "))
        }
    }
}

final class AdbClientTests: XCTestCase {
    private let adb = URL(fileURLWithPath: "/App/Contents/MacOS/adb")
    private func ok(_ stdout: String) -> FakeCommandRunner.Step { .result(CommandResult(exitCode: 0, stdout: stdout, stderr: "")) }
    private func fail(_ msg: String) -> FakeCommandRunner.Step { .result(CommandResult(exitCode: 1, stdout: "", stderr: msg)) }
    private let deviceList = """
    List of devices attached
    USB1   device usb:1-1 model:Pixel_7 transport_id:1
    """

    private func client(_ runner: FakeCommandRunner) -> AdbClient {
        var c = AdbClient(adb: adb, environment: ["PATH": "/usr/bin"], runner: runner)
        c.tcpipSettleDelay = 0
        return c
    }

    func testConnectOkFirstTry() async throws {
        let runner = FakeCommandRunner([ok("connected to 10.0.0.2:5555")])
        let serial = try await client(runner).tryConnectTcp(host: "10.0.0.2", model: "Pixel 7")
        XCTAssertEqual(serial, "10.0.0.2:5555")
        XCTAssertEqual(runner.calls, [["connect", "10.0.0.2:5555"]])
    }

    func testConnectFailsThenUsbTcpipThenRetry() async throws {
        let runner = FakeCommandRunner([
            fail("failed to connect to '10.0.0.2:5555': Connection refused"),
            ok(deviceList),
            ok("restarting in TCP mode port: 5555"),
            ok("connected to 10.0.0.2:5555"),
        ])
        let serial = try await client(runner).tryConnectTcp(host: "10.0.0.2", model: "Pixel 7")
        XCTAssertEqual(serial, "10.0.0.2:5555")
        XCTAssertEqual(runner.calls, [
            ["connect", "10.0.0.2:5555"],
            ["devices", "-l"],
            ["-s", "USB1", "tcpip", "5555"],
            ["connect", "10.0.0.2:5555"],
        ])
    }

    func testNoUsbMatchThrows() async {
        let runner = FakeCommandRunner([
            fail("cannot connect"),
            ok("List of devices attached\nUSB1 device model:Pixel_8\n"),
        ])
        do {
            _ = try await client(runner).tryConnectTcp(host: "10.0.0.2", model: "Pixel 7")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AdbError, .noUsbDeviceForTcpip(model: "Pixel 7"))
        }
    }

    func testSpawnFailurePropagates() async {
        let runner = FakeCommandRunner([.spawnError])
        do {
            _ = try await client(runner).devices()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AdbError, .spawnFailed("ENOENT"))
        }
    }

    func testTimeoutPropagates() async {
        let runner = FakeCommandRunner([.timeout])
        do {
            _ = try await client(runner).connect(host: "10.0.0.2")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AdbError, .timeout(command: "connect 10.0.0.2:5555"))
        }
    }

    func testDevicesParsesAndFailsOnNonZero() async throws {
        let runner = FakeCommandRunner([ok(deviceList), fail("boom")])
        let c = client(runner)
        let devices = try await c.devices()
        XCTAssertEqual(devices, [AdbDevice(serial: "USB1", state: "device", model: "Pixel_7")])
        do {
            _ = try await c.devices()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AdbError, .commandFailed(command: "devices -l", exitCode: 1, stderr: "boom"))
        }
    }

    func testConnectExitZeroButFailedOutput() async {
        let runner = FakeCommandRunner([ok("failed to connect to '10.0.0.2:5555'")])
        do {
            _ = try await client(runner).connect(host: "10.0.0.2")
            XCTFail("expected throw")
        } catch {
            guard case .connectFailed(let host, _)? = error as? AdbError else { return XCTFail("\(error)") }
            XCTAssertEqual(host, "10.0.0.2:5555")
        }
    }
}

final class ProcessCommandRunnerTests: XCTestCase {
    func testRunsAndCapturesOutput() async throws {
        let result = try await ProcessCommandRunner().run(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "echo out; echo err >&2; exit 4"],
            environment: ["PATH": "/usr/bin:/bin"], timeout: 5
        )
        XCTAssertEqual(result.exitCode, 4)
        XCTAssertEqual(result.stdout, "out\n")
        XCTAssertEqual(result.stderr, "err\n")
    }

    func testTimeout() async {
        do {
            _ = try await ProcessCommandRunner().run(
                URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep 30"],
                environment: ["PATH": "/usr/bin:/bin"], timeout: 0.3
            )
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? AdbError, .timeout(command: "sh -c sleep 30"))
        }
    }

    func testSpawnFailure() async {
        do {
            _ = try await ProcessCommandRunner().run(URL(fileURLWithPath: "/nonexistent"), [], environment: [:], timeout: 1)
            XCTFail("expected throw")
        } catch {
            guard case .spawnFailed? = error as? AdbError else { return XCTFail("\(error)") }
        }
    }
}
