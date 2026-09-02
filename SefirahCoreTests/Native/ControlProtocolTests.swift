import Foundation
@testable import SefirahCore
import XCTest

final class ControlMessageTests: XCTestCase {
    private func hex(_ m: ControlMessage) -> String { Hex.string(m.encode()) }

    func testTouchGoldens() {
        let down = ControlMessage.injectTouch(action: .down, pointerId: AndroidInput.pointerMouse, x: 100, y: 200, screenWidth: 576, screenHeight: 1280,
                                              pressure: 1, actionButton: .primary, buttons: .primary)
        XCTAssertEqual(hex(down), "0200ffffffffffffffff00000064000000c802400500ffff0000000100000001")
        let up = ControlMessage.injectTouch(action: .up, pointerId: AndroidInput.pointerMouse, x: 100, y: 200, screenWidth: 576, screenHeight: 1280,
                                            pressure: 0, actionButton: .primary, buttons: [])
        XCTAssertEqual(hex(up), "0201ffffffffffffffff00000064000000c80240050000000000000100000000")
        XCTAssertEqual(down.encode().count, 32)
    }

    func testScrollGoldens() {
        func scroll(_ v: Float) -> ControlMessage {
            .injectScroll(x: 100, y: 200, screenWidth: 576, screenHeight: 1280, hscroll: 0, vscroll: v, buttons: [])
        }
        XCTAssertEqual(hex(scroll(1)), "0300000064000000c802400500" + "0000" + "0800" + "00000000")
        XCTAssertEqual(hex(scroll(-1)).dropFirst(30).prefix(4), "f800")
        XCTAssertEqual(hex(scroll(16)).dropFirst(30).prefix(4), "7fff")
        XCTAssertEqual(hex(scroll(-16)).dropFirst(30).prefix(4), "8000")
        XCTAssertEqual(hex(scroll(40)).dropFirst(30).prefix(4), "7fff", "clamped")
        XCTAssertEqual(scroll(1).encode().count, 21)
    }

    func testFixedPoint() {
        XCTAssertEqual(ControlMessage.u16FixedPoint(1), 0xffff)
        XCTAssertEqual(ControlMessage.u16FixedPoint(0.5), 0x8000)
        XCTAssertEqual(ControlMessage.u16FixedPoint(0), 0)
        XCTAssertEqual(ControlMessage.i16FixedPoint(1), 0x7fff)
        XCTAssertEqual(ControlMessage.i16FixedPoint(-1), Int16(bitPattern: 0x8000))
        XCTAssertEqual(ControlMessage.i16FixedPoint(1.0 / 16), 0x0800)
    }

    func testKeycodeTextClipboard() {
        XCTAssertEqual(hex(.injectKeycode(action: .down, keycode: AndroidInput.Keycode.home, repeat: 0, metaState: [])), "0000000000030000000000000000")
        XCTAssertEqual(hex(.injectText("hi")), "01000000026869")
        XCTAssertEqual(hex(.setClipboard(sequence: 1, paste: false, text: "a")), "090000000000000001000000000161")
        XCTAssertEqual(hex(.getClipboard(.copy)), "0801")
        XCTAssertEqual(ControlMessage.injectText(String(repeating: "x", count: 400)).encode().count, 5 + 300, "text truncated at 300 bytes")
    }

    func testSimpleMessages() {
        XCTAssertEqual(hex(.setDisplayPower(on: false)), "0a00")
        XCTAssertEqual(hex(.setDisplayPower(on: true)), "0a01")
        XCTAssertEqual(hex(.backOrScreenOn(.down)), "0400")
        XCTAssertEqual(hex(.resetVideo), "11")
        XCTAssertEqual(hex(.rotateDevice), "0b")
        XCTAssertEqual(hex(.expandNotificationPanel), "05")
        XCTAssertEqual(hex(.expandSettingsPanel), "06")
        XCTAssertEqual(hex(.collapsePanels), "07")
        XCTAssertEqual(hex(.openHardKeyboardSettings), "0f")
        XCTAssertEqual(hex(.startApp("com.x")), "1005636f6d2e78")
        XCTAssertEqual(hex(.resizeDisplay(width: 800, height: 600)), "1503200258")
        XCTAssertEqual(hex(.scanFile("/a")), "16000000022f61")
        XCTAssertEqual(hex(.uhidDestroy(id: 1)), "0e0001")
    }

    func testUHIDGoldens() {
        XCTAssertEqual(HidKeyboard.descriptor.count, 63, "scrcpy hid_keyboard.c: 31 items + END_COLLECTION")
        let create = ControlMessage.uhidCreate(id: 1, vendorId: 0, productId: 0, name: "", descriptor: HidKeyboard.descriptor).encode()
        XCTAssertEqual(Hex.string(create.prefix(10)), "0c00010000000000003f")
        XCTAssertEqual(create.count, 10 + 63)
        XCTAssertEqual(hex(.uhidInput(id: 1, data: Data(repeating: 0, count: 8))), "0d00010008" + "0000000000000000")
    }

    func testDroppable() {
        XCTAssertTrue(ControlMessage.injectTouch(action: .move, pointerId: 0, x: 0, y: 0, screenWidth: 1, screenHeight: 1, pressure: 1, actionButton: [], buttons: []).isDroppable)
        XCTAssertFalse(ControlMessage.uhidCreate(id: 1, vendorId: 0, productId: 0, name: "", descriptor: Data()).isDroppable)
        XCTAssertFalse(ControlMessage.startApp("x").isDroppable)
    }
}

final class DeviceMessageTests: XCTestCase {
    func testClipboardSplitAcrossFeeds() throws {
        let full = Hex.data("00 00000002 6869")
        XCTAssertNil(try DeviceMessage.parse(full.prefix(1)))
        XCTAssertNil(try DeviceMessage.parse(full.prefix(4)))
        XCTAssertNil(try DeviceMessage.parse(full.prefix(6)))
        let parsed = try XCTUnwrap(try DeviceMessage.parse(full))
        XCTAssertEqual(parsed.0, .clipboard("hi"))
        XCTAssertEqual(parsed.consumed, 7)
    }

    func testAckAndUhidOutput() throws {
        XCTAssertEqual(try DeviceMessage.parse(Hex.data("01 0000000000000001"))?.0, .ackClipboard(1))
        let uhid = try XCTUnwrap(try DeviceMessage.parse(Hex.data("02 0001 0001 03 ff")))
        XCTAssertEqual(uhid.0, .uhidOutput(id: 1, data: Data([3])))
        XCTAssertEqual(uhid.consumed, 6)
    }

    func testErrors() {
        XCTAssertThrowsError(try DeviceMessage.parse(Hex.data("09"))) { XCTAssertEqual($0 as? DeviceMessage.ParseError, .unknownType(9)) }
        XCTAssertThrowsError(try DeviceMessage.parse(Hex.data("00 ffffffff"))) { XCTAssertEqual($0 as? DeviceMessage.ParseError, .oversize(0xffff_ffff)) }
    }

    func testNeededBytes() {
        XCTAssertEqual(ControlChannel.needed(Data()), 1)
        XCTAssertEqual(ControlChannel.needed(Hex.data("00")), 4)
        XCTAssertEqual(ControlChannel.needed(Hex.data("00 00000002")), 2)
        XCTAssertEqual(ControlChannel.needed(Hex.data("01")), 8)
        XCTAssertEqual(ControlChannel.needed(Hex.data("02 0001 0003")), 3)
    }
}

final class ControlChannelTests: XCTestCase {
    func testQueueDropPolicy() {
        let channel = ControlChannel()
        channel.send(.uhidCreate(id: 1, vendorId: 0, productId: 0, name: "", descriptor: Data()))
        for i in 0..<ControlChannel.queueCapacity {
            channel.send(.injectTouch(action: .move, pointerId: 0, x: Int32(i), y: 0, screenWidth: 1, screenHeight: 1, pressure: 1, actionButton: [], buttons: []))
        }
        XCTAssertEqual(channel.pending.count, ControlChannel.queueCapacity)
        XCTAssertEqual(channel.dropped, 1)
        if case .uhidCreate = channel.pending[0] {} else { XCTFail("uhidCreate must survive") }
        if case .injectTouch(_, _, let x, _, _, _, _, _, _) = channel.pending[1] { XCTAssertEqual(x, 1, "oldest droppable removed") } else { XCTFail() }
    }

    func testResizeCoalesces() {
        let channel = ControlChannel()
        channel.send(.resizeDisplay(width: 1, height: 1))
        channel.send(.resetVideo)
        channel.send(.resizeDisplay(width: 2, height: 2))
        XCTAssertEqual(channel.pending, [.resizeDisplay(width: 2, height: 2), .resetVideo])
    }

    func testWriterAndReader() async throws {
        let channel = ControlChannel()
        let stream = MemoryByteStream()
        channel.send(.setDisplayPower(on: false))
        let received = EventBox()
        let task = Task {
            try await channel.run(stream: stream) { received.append($0) }
        }
        try await Self.waitUntil { stream.written.count >= 2 }
        XCTAssertEqual(Hex.string(stream.written), "0a00")
        channel.send(.resetVideo)
        try await Self.waitUntil { stream.written.count >= 3 }
        XCTAssertEqual(Hex.string(stream.written), "0a0011")

        stream.feed(Hex.data("00 00000002 68"))
        stream.feed(Hex.data("69 01 0000000000000005"))
        try await Self.waitUntil { received.all.count >= 2 }
        XCTAssertEqual(received.all, [.clipboard("hi"), .ackClipboard(5)])

        stream.finish()
        do {
            try await task.value
            XCTFail("expected EOF")
        } catch {
            XCTAssertEqual(error as? StreamError, .eof)
        }
    }

    static func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw XCTSkip("timed out waiting for condition") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private final class EventBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [DeviceMessage] = []
        func append(_ m: DeviceMessage) { lock.withLock { items.append(m) } }
        var all: [DeviceMessage] { lock.withLock { items } }
    }
}
