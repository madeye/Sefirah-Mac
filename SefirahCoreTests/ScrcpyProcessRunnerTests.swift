import SefirahCore
import XCTest

final class ScrcpyProcessRunnerTests: XCTestCase {
    private func shPlan(_ script: String) -> ScrcpyLaunchPlan {
        ScrcpyLaunchPlan(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            environment: ["PATH": "/usr/bin:/bin"],
            adb: nil,
            usesBundledScrcpy: false
        )
    }

    private func run(_ runner: ScrcpyProcessRunner, _ plan: ScrcpyLaunchPlan, key: String = "k") throws -> ScrcpyExit {
        let exp = expectation(description: "exit")
        final class Box: @unchecked Sendable { var exit: ScrcpyExit? }
        let box = Box()
        try runner.launch(plan, key: key) { exit in
            box.exit = exit
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
        return box.exit!
    }

    func testFailureCapturesStderr() throws {
        let runner = ScrcpyProcessRunner()
        XCTAssertEqual(try run(runner, shPlan("echo boom >&2; exit 3")), .failure(code: 3, stderr: "boom"))
        XCTAssertTrue(runner.runningKeys.isEmpty)
    }

    func testExitTwoIsNormal() throws {
        let runner = ScrcpyProcessRunner()
        XCTAssertEqual(try run(runner, shPlan("exit 2")), .normal(code: 2))
        XCTAssertEqual(try run(runner, shPlan("exit 0")), .normal(code: 0))
    }

    func testLargeStderrIsDrained() throws {
        let runner = ScrcpyProcessRunner()
        // 200 KB > 64 KB pipe buffer: would deadlock if stderr were not drained.
        let exit = try run(runner, shPlan("i=0; while [ $i -lt 2000 ]; do printf '%0100d\\n' $i >&2; i=$((i+1)); done; exit 0"))
        XCTAssertEqual(exit, .normal(code: 0))
    }

    func testFailureStderrIsBoundedTail() throws {
        let runner = ScrcpyProcessRunner()
        let exit = try run(runner, shPlan("i=0; while [ $i -lt 2000 ]; do printf '%0100d\\n' $i >&2; i=$((i+1)); done; echo LAST >&2; exit 1"))
        guard case .failure(let code, let stderr) = exit else { return XCTFail("expected failure") }
        XCTAssertEqual(code, 1)
        XCTAssertTrue(stderr.hasSuffix("LAST"))
        XCTAssertLessThanOrEqual(stderr.utf8.count, ScrcpyProcessRunner.stderrTailBytes)
    }

    func testRelaunchSameKeyTerminatesFirst() throws {
        let runner = ScrcpyProcessRunner()
        let first = expectation(description: "first exit")
        try runner.launch(shPlan("sleep 30"), key: "k") { exit in
            if case .signaled(15, _) = exit { first.fulfill() } else { XCTFail("unexpected \(exit)") }
        }
        XCTAssertEqual(runner.runningKeys, ["k"])
        let second = expectation(description: "second exit")
        try runner.launch(shPlan("exit 0"), key: "k") { _ in second.fulfill() }
        wait(for: [first, second], timeout: 10)
        XCTAssertTrue(runner.runningKeys.isEmpty)
    }

    func testTerminateAll() throws {
        let runner = ScrcpyProcessRunner()
        let a = expectation(description: "a"), b = expectation(description: "b")
        try runner.launch(shPlan("sleep 30"), key: "a") { _ in a.fulfill() }
        try runner.launch(shPlan("sleep 30"), key: "b") { _ in b.fulfill() }
        XCTAssertEqual(runner.runningKeys, ["a", "b"])
        runner.terminateAll()
        wait(for: [a, b], timeout: 10)
        XCTAssertTrue(runner.runningKeys.isEmpty)
    }

    func testSpawnFailureThrows() {
        let runner = ScrcpyProcessRunner()
        let plan = ScrcpyLaunchPlan(executable: URL(fileURLWithPath: "/nonexistent/bin"), arguments: [], environment: [:], adb: nil, usesBundledScrcpy: false)
        XCTAssertThrowsError(try runner.launch(plan, key: "x") { _ in })
        XCTAssertTrue(runner.runningKeys.isEmpty)
    }
}
