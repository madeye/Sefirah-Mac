import AppKit
import Foundation
@testable import SefirahCore
import XCTest

final class PointerMapperTests: XCTestCase {
    func testPortraitVideoInLandscapeView() {
        // 576×1280 video letterboxed in a 1000×500 view: scale 0.390625 → 225×500 centred at x=387.5.
        let m = PointerMapper(viewSize: CGSize(width: 1000, height: 500), videoSize: CGSize(width: 576, height: 1280))
        XCTAssertEqual(m.videoRect.minX, 387.5)
        XCTAssertEqual(m.videoRect.width, 225)
        XCTAssertEqual(m.videoRect.height, 500)
        // Top-left corner of the video (AppKit y is bottom-up).
        let tl = m.toFrame(CGPoint(x: 387.5, y: 500))
        XCTAssertEqual(tl?.x, 0)
        XCTAssertEqual(tl?.y, 0)
        // Centre.
        let c = m.toFrame(CGPoint(x: 500, y: 250))
        XCTAssertEqual(c?.x, 288)
        XCTAssertEqual(c?.y, 640)
        // Bottom-right is clamped inside the frame.
        let br = m.toFrame(CGPoint(x: 612.5, y: 0))
        XCTAssertEqual(br?.x, 575)
        XCTAssertEqual(br?.y, 1279)
    }

    func testYFlipExactFit() {
        let m = PointerMapper(viewSize: CGSize(width: 288, height: 640), videoSize: CGSize(width: 576, height: 1280))
        let p = m.toFrame(CGPoint(x: 100, y: 540)) // 100 points from the top
        XCTAssertEqual(p?.x, 200)
        XCTAssertEqual(p?.y, 200)
    }

    func testOutsideAndClamp() {
        let m = PointerMapper(viewSize: CGSize(width: 1000, height: 500), videoSize: CGSize(width: 576, height: 1280))
        XCTAssertNil(m.toFrame(CGPoint(x: 10, y: 250)))
        let clamped = m.toFrame(CGPoint(x: 10, y: 250), clamp: true)
        XCTAssertEqual(clamped?.x, 0)
        XCTAssertEqual(clamped?.y, 640)
        XCTAssertNil(m.toFrame(CGPoint(x: 500, y: 600)))
        XCTAssertFalse(PointerMapper(viewSize: .zero, videoSize: CGSize(width: 1, height: 1)).isValid)
        XCTAssertNil(PointerMapper(viewSize: CGSize(width: 10, height: 10), videoSize: .zero).toFrame(.zero, clamp: true))
    }

    func testMirroredPoint() {
        let m = PointerMapper.mirrored((x: 100, y: 200), in: CGSize(width: 576, height: 1280))
        XCTAssertEqual(m.x, 475)
        XCTAssertEqual(m.y, 1079)
    }
}

final class MacKeyMapTests: XCTestCase {
    func testKeycodeSpotChecks() {
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.a), 29)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.z), 54)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.digit0), 7)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.digit9), 16)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.return), 66)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.keypadEnter), 160)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.escape), 111)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.delete), 67)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.forwardDelete), 112)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.tab), 61)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.space), 62)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.home), 122)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.end), 123)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.pageUp), 92)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.pageDown), 93)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.leftArrow), 21)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.upArrow), 19)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.help), 124)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.f1), 131)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.f12), 142)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.grave), 68)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.quote), 75)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.slash), 76)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.keypad0), 144)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.keypad9), 153)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.keypadDivide), 154)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.keypadEquals), 161)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.volumeUp), 24)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.mute), 164)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.command), 117)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.rightCommand), 118)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.option), 57)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.control), 113)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.shift), 59)
        XCTAssertEqual(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.capsLock), 115)
        XCTAssertNil(MacKeyMap.androidKeycode(virtualKey: MacVirtualKey.function))
    }

    func testHidUsages() {
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.a), 0x04)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.z), 0x1d)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.digit1), 0x1e)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.digit0), 0x27)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.return), 0x28)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.space), 0x2c)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.capsLock), 0x39)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.f12), 0x45)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.rightArrow), 0x4f)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.upArrow), 0x52)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.keypad1), 0x59)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.keypad0), 0x62)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.keypadEquals), 0x67)
        XCTAssertEqual(MacKeyMap.hidUsage(virtualKey: MacVirtualKey.command), 0xe3)
    }

    func testMetaState() {
        XCTAssertEqual(MacKeyMap.metaState([]), [])
        XCTAssertEqual(MacKeyMap.metaState([.leftCommand]), [.metaOn, .metaLeft])
        XCTAssertEqual(MacKeyMap.metaState([.rightOption]), [.altOn, .altRight])
        XCTAssertEqual(MacKeyMap.metaState([.leftControl, .leftShift]).rawValue, 0x1000 | 0x2000 | 0x1 | 0x40)
        XCTAssertEqual(MacKeyMap.metaState([.capsLock]).rawValue, 0x100000)
        XCTAssertEqual(MacKeyMap.hidModifiers([.leftControl, .rightGuiEquivalent]), [.leftControl, .rightGui])
    }

    func testModifierFlagsSides() {
        let left = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x0002)
        XCTAssertEqual(MacModifiers(flags: left), [.leftShift])
        let right = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x0010)
        XCTAssertEqual(MacModifiers(flags: right), [.rightCommand])
        XCTAssertEqual(MacModifiers(flags: [.control]), [.leftControl], "no side bit → left")
        XCTAssertEqual(MacModifiers(flags: [.option, .capsLock]), [.leftOption, .capsLock])
    }

    func testMixedModeDecisions() {
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.a, characters: "a", modifiers: []), .keycode(29))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.a, characters: "A", modifiers: [.leftShift]), .keycode(29))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.e, characters: "é", modifiers: [.leftOption]), .text("é"))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.space, characters: " ", modifiers: []), .keycode(62))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.digit1, characters: "1", modifiers: []), .text("1"))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.digit1, characters: "!", modifiers: [.leftShift]), .text("!"))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.digit1, characters: "1", modifiers: [.leftCommand]), .keycode(8))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.comma, characters: ",", modifiers: [.leftControl]), .keycode(55))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.return, characters: "\r", modifiers: []), .keycode(66))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.leftArrow, characters: "\u{F702}", modifiers: []), .keycode(21))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.a, characters: "\u{01}", modifiers: [.leftControl]), .keycode(29))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: 0xff, characters: "", modifiers: []), .ignore)
        XCTAssertEqual(MacKeyMap.decide(virtualKey: 0xff, characters: "ß", modifiers: []), .text("ß"))
        XCTAssertEqual(MacKeyMap.decide(virtualKey: MacVirtualKey.keypad5, characters: "5", modifiers: []), .keycode(149))
    }

    func testTextChunking() {
        XCTAssertEqual(ControlMessage.textChunks(""), [])
        XCTAssertEqual(ControlMessage.textChunks("hi"), ["hi"])
        let long = String(repeating: "a", count: 299) + "é" + "b" // é is 2 bytes → must not straddle the 300-byte boundary
        let chunks = ControlMessage.textChunks(long)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].utf8.count, 299)
        XCTAssertEqual(chunks[1], "éb")
        for chunk in ControlMessage.textChunks(String(repeating: "日本", count: 200)) {
            XCTAssertLessThanOrEqual(chunk.utf8.count, ControlMessage.maxTextBytes)
        }
        XCTAssertEqual(ControlMessage.textChunks(String(repeating: "日本", count: 200)).joined(), String(repeating: "日本", count: 200))
    }
}

extension MacModifiers {
    /// Test alias so the intent reads clearly in `testMetaState`.
    static let rightGuiEquivalent = MacModifiers.rightCommand
}

final class HidKeyboardTests: XCTestCase {
    func testDescriptor() {
        XCTAssertEqual(HidKeyboard.descriptor.count, 63)
        XCTAssertEqual(HidKeyboard.descriptor.first, 0x05)
        XCTAssertEqual(HidKeyboard.descriptor.last, 0xC0)
        XCTAssertEqual(Hex.string(HidKeyboard.createMessage.encode().prefix(10)), "0c00010000000000003f")
    }

    func testReport() {
        XCTAssertEqual(Hex.string(HidKeyboard.report(modifiers: [], keys: [])), "0000000000000000")
        XCTAssertEqual(Hex.string(HidKeyboard.report(modifiers: [.leftShift], keys: [0x04])), "0200040000000000")
        XCTAssertEqual(Hex.string(HidKeyboard.report(modifiers: [.leftControl, .rightGui], keys: [0x04, 0x05, 0x06, 0x07, 0x08, 0x09])), "8100040506070809")
        XCTAssertEqual(Hex.string(HidKeyboard.report(modifiers: [], keys: [1, 2, 3, 4, 5, 6, 7])), "0000010101010101", "phantom state")
        XCTAssertEqual(HidKeyboard.Leds(rawValue: 0x03), [.numLock, .capsLock])
    }
}
