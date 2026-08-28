import SefirahCore
import XCTest

final class CompanionHelpersTests: XCTestCase {
    func testScrcpyArgumentsIncludeSerialScreenOffAndPackage() {
        var settings = DeviceSettings(deviceId: "d")
        settings.screenOff = true
        settings.physicalKeyboard = true
        settings.scrcpyClipboardAutosync = false
        settings.frameRate = 60
        settings.display = "0"
        settings.audioOutputMode = .remote
        let args = ScrcpyArguments.build(
            settings: settings,
            serial: "SERIAL",
            package: "com.foo",
            appName: "Foo"
        )
        XCTAssertTrue(args.contains("--start-app=com.foo"))
        XCTAssertTrue(args.contains("--turn-screen-off"))
        XCTAssertTrue(args.contains("--keyboard=uhid"))
        XCTAssertTrue(args.contains("--no-clipboard-autosync"))
        XCTAssertTrue(args.contains("--no-audio"))
        XCTAssertTrue(args.contains("-s"))
        XCTAssertTrue(args.contains("SERIAL"))
        XCTAssertTrue(args.contains("--max-fps=60"))
    }

    func testSftpFinderURLEmbedsUserPortAndPath() {
        let url = SftpBrowse.finderURL(
            host: "192.168.1.8",
            port: 2222,
            username: "u",
            password: "p",
            path: "/sdcard"
        )
        XCTAssertEqual(url?.scheme, "sftp")
        XCTAssertEqual(url?.user, "u")
        XCTAssertEqual(url?.port, 2222)
        XCTAssertTrue(url?.path.hasPrefix("/sdcard") == true)
    }

    func testActionRunnerLinkPowerRun() {
        let link = ActionRunner.plan(ActionItem(actionId: "link", settings: ["url": "https://example.com"]))
        XCTAssertEqual(link.command, "open")
        XCTAssertEqual(link.arguments, ["https://example.com"])

        let run = ActionRunner.plan(ActionItem(actionId: "run", settings: ["path": "/bin/echo", "arguments": "hi"]))
        XCTAssertEqual(run.command, "/bin/echo")
        XCTAssertEqual(run.arguments, ["hi"])

        let sleep = ActionRunner.plan(ActionItem(actionId: "power", settings: ["powerKind": "Sleep"]))
        XCTAssertEqual(sleep.command, "/usr/bin/pmset")
        XCTAssertEqual(sleep.arguments, ["sleepnow"])

        let hibernate = ActionRunner.plan(ActionItem(actionId: "power", settings: ["powerKind": "Hibernate"]))
        XCTAssertEqual(hibernate.command, "")

        let lock = ActionRunner.plan(ActionItem(actionId: "power", settings: ["powerKind": "Lock"]))
        XCTAssertEqual(lock.command, "/usr/bin/osascript")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: lock.command))
        XCTAssertFalse(lock.command.contains("CGSession"))
        let script = lock.arguments.joined(separator: " ")
        XCTAssertTrue(script.contains("keystroke"))
        XCTAssertTrue(script.contains("control down"))
        XCTAssertTrue(script.contains("command down"))
    }

    func testActionListUsesCatalogIdsAndEncodes() throws {
        let items = [
            ActionItem(id: "abc", name: "Lock", actionId: "power", settings: ["powerKind": "Lock"]),
        ]
        let list = ActionRunner.actionList(from: items)
        XCTAssertEqual(list.actions.first?.actionId, "abc")
        XCTAssertEqual(list.actions.first?.actionName, "Lock")
        let encoded = try NDJSONCodec.encodeMessage(.actionList(list))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "ActionList")
        XCTAssertEqual(try NDJSONCodec.decodeMessage(from: encoded), .actionList(list))
    }
}
