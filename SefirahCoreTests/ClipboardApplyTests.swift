import AppKit
import SefirahCore
import XCTest

final class ClipboardApplyTests: XCTestCase {
    func testApplyTextWritesPasteboardString() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let info = ClipboardInfo(clipboardType: "text/plain", content: "from-phone")
        XCTAssertTrue(ClipboardApply.apply(info, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "from-phone")
    }

    func testApplyPNGWritesPasteboardImage() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let png = makePNG()
        let info = ClipboardInfo(clipboardType: "image/png", content: png.base64EncodedString())
        XCTAssertTrue(ClipboardApply.apply(info, to: pasteboard))
        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        XCTAssertEqual(images?.count, 1)
        XCTAssertNotNil(images?.first)
    }

    func testApplyFilePutsTextOnPasteboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).txt")
        try "clip-file".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(ClipboardApply.applyFile(url, mimeType: "text/plain", to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "clip-file")
    }

    private func makePNG() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }
}
