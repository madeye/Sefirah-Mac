@testable import SefirahCore
import XCTest

final class BundledToolsTests: XCTestCase {
    private let macos = URL(fileURLWithPath: "/App.app/Contents/MacOS", isDirectory: true)
    private let resources = URL(fileURLWithPath: "/App.app/Contents/Resources", isDirectory: true)

    private func locate(missing: Set<String> = [], version: String? = "4.1\n") -> BundledTools? {
        BundledTools.locate(
            auxiliaryExecutable: { macos.appendingPathComponent($0) },
            resourcesRoot: resources,
            exists: { !missing.contains($0.lastPathComponent) },
            readVersion: { _ in version }
        )
    }

    func testAllPresent() {
        let tools = locate()
        XCTAssertEqual(tools?.scrcpy.path, "/App.app/Contents/MacOS/scrcpy")
        XCTAssertEqual(tools?.adb.path, "/App.app/Contents/MacOS/adb")
        XCTAssertEqual(tools?.server.path, "/App.app/Contents/Resources/scrcpy/scrcpy-server")
        XCTAssertEqual(tools?.version, "4.1")
    }

    func testMissingBinariesReturnNil() {
        XCTAssertNil(locate(missing: ["scrcpy"]))
        XCTAssertNil(locate(missing: ["adb"]))
        XCTAssertNil(locate(missing: ["scrcpy-server"]))
    }

    func testMissingVersionIsNil() {
        XCTAssertNil(locate(version: nil)?.version)
        XCTAssertNotNil(locate(version: nil))
        XCTAssertNil(locate(version: "  \n")?.version)
    }

    func testNoResourcesRootIsNil() {
        XCTAssertNil(BundledTools.locate(
            auxiliaryExecutable: { macos.appendingPathComponent($0) },
            resourcesRoot: nil,
            exists: { _ in true },
            readVersion: { _ in nil }
        ))
    }
}
