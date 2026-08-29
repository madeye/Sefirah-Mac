import SefirahCore
import XCTest

final class ScrcpyDiagnosticsTests: XCTestCase {
    private func hint(_ stderr: String) -> String? {
        ScrcpyDiagnostics.hint(exit: .failure(code: 1, stderr: stderr))
    }

    func testPatterns() {
        XCTAssertTrue(hint("adb: error: no devices/emulators found")!.contains("No Android device"))
        XCTAssertTrue(hint("ERROR: Could not find any ADB device")!.contains("No Android device"))
        XCTAssertTrue(hint("error: device unauthorized.")!.contains("USB-debugging prompt"))
        XCTAssertTrue(hint("adb: more than one device/emulator")!.contains("Several devices"))
        XCTAssertTrue(hint("ERROR: The server version (4.0) does not match the client (4.1)")!.contains("scrcpy-server does not match"))
        XCTAssertTrue(hint("error: device offline")!.contains("offline"))
    }

    func testUnknownIsNil() {
        XCTAssertNil(hint("something else entirely"))
        XCTAssertNil(hint(""))
        XCTAssertNil(ScrcpyDiagnostics.hint(exit: .normal(code: 0)))
    }

    func testSigkillHint() {
        XCTAssertTrue(ScrcpyDiagnostics.hint(exit: .signaled(9, stderr: ""))!.contains("Reinstall Sefirah"))
        XCTAssertNil(ScrcpyDiagnostics.hint(exit: .signaled(15, stderr: "")))
    }
}
