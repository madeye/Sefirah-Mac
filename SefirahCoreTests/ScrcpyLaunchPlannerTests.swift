import SefirahCore
import XCTest

final class ScrcpyLaunchPlannerTests: XCTestCase {
    private let bundled = BundledTools(
        scrcpy: URL(fileURLWithPath: "/App/Contents/MacOS/scrcpy"),
        adb: URL(fileURLWithPath: "/App/Contents/MacOS/adb"),
        server: URL(fileURLWithPath: "/App/Contents/Resources/scrcpy/scrcpy-server"),
        version: "4.1"
    )

    private func plan(
        general: GeneralSettings = GeneralSettings(),
        device: DeviceSettings = DeviceSettings(deviceId: "d"),
        bundled: BundledTools?,
        serial: String? = nil,
        env: [String: String] = [:],
        executables: Set<String>? = nil
    ) throws -> ScrcpyLaunchPlan {
        try ScrcpyLaunchPlanner.plan(
            general: general, device: device, bundled: bundled, serial: serial,
            baseEnvironment: env, home: "/Users/test",
            isExecutable: { url in executables.map { set in set.contains { url.path.hasPrefix($0) } } ?? true }
        )
    }

    func testBundledSetsAdbAndServer() throws {
        let p = try plan(bundled: bundled)
        XCTAssertEqual(p.executable.path, "/App/Contents/MacOS/scrcpy")
        XCTAssertEqual(p.environment["ADB"], "/App/Contents/MacOS/adb")
        XCTAssertEqual(p.environment["SCRCPY_SERVER_PATH"], "/App/Contents/Resources/scrcpy/scrcpy-server")
        XCTAssertTrue(p.usesBundledScrcpy)
        XCTAssertEqual(p.adb?.path, "/App/Contents/MacOS/adb")
    }

    func testGeneralOverrideWinsOverDeviceOverBundled() throws {
        var general = GeneralSettings()
        general.scrcpyPath = "/g/scrcpy"
        var device = DeviceSettings(deviceId: "d")
        device.scrcpyPath = "/d/scrcpy"
        XCTAssertEqual(try plan(general: general, device: device, bundled: bundled).executable.path, "/g/scrcpy")
        XCTAssertEqual(try plan(device: device, bundled: bundled).executable.path, "/d/scrcpy")
        XCTAssertEqual(try plan(bundled: bundled).executable.path, "/App/Contents/MacOS/scrcpy")
    }

    func testOverrideScrcpyKeepsBundledAdbButNoServer() throws {
        var general = GeneralSettings()
        general.scrcpyPath = "/opt/homebrew/bin/scrcpy"
        let p = try plan(general: general, bundled: bundled)
        XCTAssertFalse(p.usesBundledScrcpy)
        XCTAssertNil(p.environment["SCRCPY_SERVER_PATH"])
        XCTAssertEqual(p.environment["ADB"], "/App/Contents/MacOS/adb")
    }

    func testOverrideNotExecutableThrowsWithoutFallback() {
        var general = GeneralSettings()
        general.scrcpyPath = "/nonexistent/scrcpy"
        XCTAssertThrowsError(try plan(general: general, bundled: bundled, executables: ["/App/"])) { error in
            XCTAssertEqual(error as? ScrcpyLaunchError, .overrideNotFound(tool: "scrcpy", path: "/nonexistent/scrcpy"))
        }
        var adbOnly = GeneralSettings()
        adbOnly.adbPath = "/nonexistent/adb"
        XCTAssertThrowsError(try plan(general: adbOnly, bundled: bundled, executables: ["/App/"])) { error in
            XCTAssertEqual(error as? ScrcpyLaunchError, .overrideNotFound(tool: "adb", path: "/nonexistent/adb"))
        }
    }

    func testNothingAvailableThrows() {
        XCTAssertThrowsError(try plan(bundled: nil)) { error in
            XCTAssertEqual(error as? ScrcpyLaunchError, .scrcpyUnavailable)
        }
    }

    func testBundledToolMissingThrows() {
        XCTAssertThrowsError(try plan(bundled: bundled, executables: ["/App/Contents/MacOS/scrcpy"])) { error in
            XCTAssertEqual(error as? ScrcpyLaunchError, .bundledToolMissing("adb"))
        }
    }

    func testEnvironmentDefaults() throws {
        let p = try plan(bundled: bundled, env: ["FOO": "bar"])
        XCTAssertEqual(p.environment["FOO"], "bar")
        XCTAssertEqual(p.environment["HOME"], "/Users/test")
        XCTAssertEqual(p.environment["PATH"], ScrcpyLaunchPlanner.defaultPath)
        XCTAssertNil(p.environment["ANDROID_ADB_SERVER_PORT"])

        let kept = try plan(bundled: bundled, env: ["HOME": "/h", "PATH": "/p"])
        XCTAssertEqual(kept.environment["HOME"], "/h")
        XCTAssertEqual(kept.environment["PATH"], "/p")
    }

    func testArgumentsMatchBuilder() throws {
        var device = DeviceSettings(deviceId: "d")
        device.customArguments = "--stay-awake"
        let p = try plan(device: device, bundled: bundled, serial: "S1")
        XCTAssertEqual(p.arguments, ScrcpyArguments.build(settings: device, serial: "S1"))
        XCTAssertTrue(p.arguments.contains("S1"))
    }

    func testErrorDescriptions() {
        XCTAssertTrue(ScrcpyLaunchError.bundledToolMissing("adb").localizedDescription.contains("(adb)"))
        XCTAssertTrue(ScrcpyLaunchError.overrideNotFound(tool: "scrcpy", path: "/opt/x").localizedDescription.contains("/opt/x"))
    }
}
