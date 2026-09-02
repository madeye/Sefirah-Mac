import AppKit
import Foundation

/// macOS virtual key codes (`Carbon.HIToolbox/Events.h`), kept as raw values so the mapping is pure and testable.
public enum MacVirtualKey {
    public static let a: UInt16 = 0x00, s: UInt16 = 0x01, d: UInt16 = 0x02, f: UInt16 = 0x03, h: UInt16 = 0x04, g: UInt16 = 0x05
    public static let z: UInt16 = 0x06, x: UInt16 = 0x07, c: UInt16 = 0x08, v: UInt16 = 0x09, b: UInt16 = 0x0B, q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D, e: UInt16 = 0x0E, r: UInt16 = 0x0F, y: UInt16 = 0x10, t: UInt16 = 0x11
    public static let digit1: UInt16 = 0x12, digit2: UInt16 = 0x13, digit3: UInt16 = 0x14, digit4: UInt16 = 0x15, digit6: UInt16 = 0x16
    public static let digit5: UInt16 = 0x17, equal: UInt16 = 0x18, digit9: UInt16 = 0x19, digit7: UInt16 = 0x1A, minus: UInt16 = 0x1B
    public static let digit8: UInt16 = 0x1C, digit0: UInt16 = 0x1D, rightBracket: UInt16 = 0x1E, o: UInt16 = 0x1F, u: UInt16 = 0x20
    public static let leftBracket: UInt16 = 0x21, i: UInt16 = 0x22, p: UInt16 = 0x23, l: UInt16 = 0x25, j: UInt16 = 0x26
    public static let quote: UInt16 = 0x27, k: UInt16 = 0x28, semicolon: UInt16 = 0x29, backslash: UInt16 = 0x2A, comma: UInt16 = 0x2B
    public static let slash: UInt16 = 0x2C, n: UInt16 = 0x2D, m: UInt16 = 0x2E, period: UInt16 = 0x2F, grave: UInt16 = 0x32
    public static let keypadDecimal: UInt16 = 0x41, keypadMultiply: UInt16 = 0x43, keypadPlus: UInt16 = 0x45, keypadClear: UInt16 = 0x47
    public static let keypadDivide: UInt16 = 0x4B, keypadEnter: UInt16 = 0x4C, keypadMinus: UInt16 = 0x4E, keypadEquals: UInt16 = 0x51
    public static let keypad0: UInt16 = 0x52, keypad1: UInt16 = 0x53, keypad2: UInt16 = 0x54, keypad3: UInt16 = 0x55, keypad4: UInt16 = 0x56
    public static let keypad5: UInt16 = 0x57, keypad6: UInt16 = 0x58, keypad7: UInt16 = 0x59, keypad8: UInt16 = 0x5B, keypad9: UInt16 = 0x5C
    public static let `return`: UInt16 = 0x24, tab: UInt16 = 0x30, space: UInt16 = 0x31, delete: UInt16 = 0x33, escape: UInt16 = 0x35
    public static let command: UInt16 = 0x37, shift: UInt16 = 0x38, capsLock: UInt16 = 0x39, option: UInt16 = 0x3A, control: UInt16 = 0x3B
    public static let rightCommand: UInt16 = 0x36, rightShift: UInt16 = 0x3C, rightOption: UInt16 = 0x3D, rightControl: UInt16 = 0x3E
    public static let function: UInt16 = 0x3F
    public static let volumeUp: UInt16 = 0x48, volumeDown: UInt16 = 0x49, mute: UInt16 = 0x4A
    public static let f5: UInt16 = 0x60, f6: UInt16 = 0x61, f7: UInt16 = 0x62, f3: UInt16 = 0x63, f8: UInt16 = 0x64, f9: UInt16 = 0x65
    public static let f11: UInt16 = 0x67, f10: UInt16 = 0x6D, f12: UInt16 = 0x6F, f4: UInt16 = 0x76, f2: UInt16 = 0x78, f1: UInt16 = 0x7A
    public static let help: UInt16 = 0x72, home: UInt16 = 0x73, pageUp: UInt16 = 0x74, forwardDelete: UInt16 = 0x75, end: UInt16 = 0x77
    public static let pageDown: UInt16 = 0x79, leftArrow: UInt16 = 0x7B, rightArrow: UInt16 = 0x7C, downArrow: UInt16 = 0x7D, upArrow: UInt16 = 0x7E
}

/// Modifier state with left/right distinction (from `NSEvent.modifierFlags` device-dependent bits).
public struct MacModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let leftShift = MacModifiers(rawValue: 1 << 0)
    public static let rightShift = MacModifiers(rawValue: 1 << 1)
    public static let leftControl = MacModifiers(rawValue: 1 << 2)
    public static let rightControl = MacModifiers(rawValue: 1 << 3)
    public static let leftOption = MacModifiers(rawValue: 1 << 4)
    public static let rightOption = MacModifiers(rawValue: 1 << 5)
    public static let leftCommand = MacModifiers(rawValue: 1 << 6)
    public static let rightCommand = MacModifiers(rawValue: 1 << 7)
    public static let capsLock = MacModifiers(rawValue: 1 << 8)

    public static let shift: MacModifiers = [.leftShift, .rightShift]
    public static let control: MacModifiers = [.leftControl, .rightControl]
    public static let option: MacModifiers = [.leftOption, .rightOption]
    public static let command: MacModifiers = [.leftCommand, .rightCommand]

    public var hasShift: Bool { !isDisjoint(with: Self.shift) }
    public var hasControl: Bool { !isDisjoint(with: Self.control) }
    public var hasOption: Bool { !isDisjoint(with: Self.option) }
    public var hasCommand: Bool { !isDisjoint(with: Self.command) }

    /// `NX_DEVICE*KEYMASK` bits carried by `NSEvent.modifierFlags`; falls back to the left side when only
    /// the device-independent bit is present (synthesised events).
    public init(flags: NSEvent.ModifierFlags) {
        let raw = flags.rawValue
        var m: MacModifiers = []
        func side(_ independent: NSEvent.ModifierFlags, _ leftMask: UInt, _ rightMask: UInt, _ left: MacModifiers, _ right: MacModifiers) {
            guard flags.contains(independent) else { return }
            if raw & leftMask != 0 { m.insert(left) }
            if raw & rightMask != 0 { m.insert(right) }
            if raw & (leftMask | rightMask) == 0 { m.insert(left) }
        }
        side(.shift, 0x0002, 0x0004, .leftShift, .rightShift)
        side(.control, 0x0001, 0x2000, .leftControl, .rightControl)
        side(.option, 0x0020, 0x0040, .leftOption, .rightOption)
        side(.command, 0x0008, 0x0010, .leftCommand, .rightCommand)
        if flags.contains(.capsLock) { m.insert(.capsLock) }
        self = m
    }
}

/// kVK → Android keycode / HID usage, modifier → metastate, and the SDK mixed-mode inject decision.
public enum MacKeyMap {
    public enum Decision: Equatable, Sendable {
        case keycode(Int32)
        case text(String)
        case ignore
    }

    // MARK: Tables

    private static let letters: [UInt16: Int] = [
        MacVirtualKey.a: 0, MacVirtualKey.b: 1, MacVirtualKey.c: 2, MacVirtualKey.d: 3, MacVirtualKey.e: 4, MacVirtualKey.f: 5,
        MacVirtualKey.g: 6, MacVirtualKey.h: 7, MacVirtualKey.i: 8, MacVirtualKey.j: 9, MacVirtualKey.k: 10, MacVirtualKey.l: 11,
        MacVirtualKey.m: 12, MacVirtualKey.n: 13, MacVirtualKey.o: 14, MacVirtualKey.p: 15, MacVirtualKey.q: 16, MacVirtualKey.r: 17,
        MacVirtualKey.s: 18, MacVirtualKey.t: 19, MacVirtualKey.u: 20, MacVirtualKey.v: 21, MacVirtualKey.w: 22, MacVirtualKey.x: 23,
        MacVirtualKey.y: 24, MacVirtualKey.z: 25,
    ]

    private static let digits: [UInt16: Int] = [
        MacVirtualKey.digit0: 0, MacVirtualKey.digit1: 1, MacVirtualKey.digit2: 2, MacVirtualKey.digit3: 3, MacVirtualKey.digit4: 4,
        MacVirtualKey.digit5: 5, MacVirtualKey.digit6: 6, MacVirtualKey.digit7: 7, MacVirtualKey.digit8: 8, MacVirtualKey.digit9: 9,
    ]

    private static let keypadDigits: [UInt16: Int] = [
        MacVirtualKey.keypad0: 0, MacVirtualKey.keypad1: 1, MacVirtualKey.keypad2: 2, MacVirtualKey.keypad3: 3, MacVirtualKey.keypad4: 4,
        MacVirtualKey.keypad5: 5, MacVirtualKey.keypad6: 6, MacVirtualKey.keypad7: 7, MacVirtualKey.keypad8: 8, MacVirtualKey.keypad9: 9,
    ]

    private static let functionKeys: [UInt16: Int] = [
        MacVirtualKey.f1: 1, MacVirtualKey.f2: 2, MacVirtualKey.f3: 3, MacVirtualKey.f4: 4, MacVirtualKey.f5: 5, MacVirtualKey.f6: 6,
        MacVirtualKey.f7: 7, MacVirtualKey.f8: 8, MacVirtualKey.f9: 9, MacVirtualKey.f10: 10, MacVirtualKey.f11: 11, MacVirtualKey.f12: 12,
    ]

    /// Navigation, editing, modifier and function keys: sent as keycodes in every mode (scrcpy `special_keys`).
    private static let specialKeys: [UInt16: Int32] = {
        typealias K = AndroidInput.Keycode
        var t: [UInt16: Int32] = [
            MacVirtualKey.return: K.enter, MacVirtualKey.keypadEnter: K.numpadEnter, MacVirtualKey.escape: K.escape,
            MacVirtualKey.delete: K.del, MacVirtualKey.forwardDelete: K.forwardDel, MacVirtualKey.tab: K.tab,
            MacVirtualKey.home: K.moveHome, MacVirtualKey.end: K.moveEnd, MacVirtualKey.pageUp: K.pageUp, MacVirtualKey.pageDown: K.pageDown,
            MacVirtualKey.leftArrow: K.dpadLeft, MacVirtualKey.rightArrow: K.dpadRight, MacVirtualKey.upArrow: K.dpadUp, MacVirtualKey.downArrow: K.dpadDown,
            MacVirtualKey.help: K.insert,
            MacVirtualKey.command: K.metaLeft, MacVirtualKey.rightCommand: K.metaRight,
            MacVirtualKey.option: K.altLeft, MacVirtualKey.rightOption: K.altRight,
            MacVirtualKey.control: K.ctrlLeft, MacVirtualKey.rightControl: K.ctrlRight,
            MacVirtualKey.shift: K.shiftLeft, MacVirtualKey.rightShift: K.shiftRight,
            MacVirtualKey.capsLock: K.capsLock,
            MacVirtualKey.volumeUp: K.volumeUp, MacVirtualKey.volumeDown: K.volumeDown, MacVirtualKey.mute: K.volumeMute,
            MacVirtualKey.keypadDivide: K.numpadDivide, MacVirtualKey.keypadMultiply: K.numpadMultiply, MacVirtualKey.keypadMinus: K.numpadSubtract,
            MacVirtualKey.keypadPlus: K.numpadAdd, MacVirtualKey.keypadDecimal: K.numpadDot, MacVirtualKey.keypadEquals: K.numpadEquals,
            MacVirtualKey.keypadClear: K.numLock,
        ]
        for (vk, n) in functionKeys { t[vk] = K.function(n) }
        for (vk, n) in keypadDigits { t[vk] = K.numpad(n) }
        return t
    }()

    /// Punctuation on the US layout; keycodes only when a shortcut modifier is held (otherwise text).
    private static let punctuation: [UInt16: Int32] = {
        typealias K = AndroidInput.Keycode
        return [
            MacVirtualKey.comma: K.comma, MacVirtualKey.period: K.period, MacVirtualKey.grave: K.grave, MacVirtualKey.minus: K.minus,
            MacVirtualKey.equal: K.equals, MacVirtualKey.leftBracket: K.leftBracket, MacVirtualKey.rightBracket: K.rightBracket,
            MacVirtualKey.backslash: K.backslash, MacVirtualKey.semicolon: K.semicolon, MacVirtualKey.quote: K.apostrophe,
            MacVirtualKey.slash: K.slash,
        ]
    }()

    /// USB HID usage page 7 ids for the UHID keyboard.
    private static let hidUsages: [UInt16: UInt8] = {
        var t: [UInt16: UInt8] = [:]
        for (vk, i) in letters { t[vk] = UInt8(0x04 + i) }
        for (vk, n) in digits { t[vk] = n == 0 ? 0x27 : UInt8(0x1e + n - 1) }
        for (vk, n) in functionKeys { t[vk] = UInt8(0x3a + n - 1) }
        for (vk, n) in keypadDigits { t[vk] = n == 0 ? 0x62 : UInt8(0x59 + n - 1) }
        t[MacVirtualKey.return] = 0x28; t[MacVirtualKey.escape] = 0x29; t[MacVirtualKey.delete] = 0x2a; t[MacVirtualKey.tab] = 0x2b
        t[MacVirtualKey.space] = 0x2c; t[MacVirtualKey.minus] = 0x2d; t[MacVirtualKey.equal] = 0x2e; t[MacVirtualKey.leftBracket] = 0x2f
        t[MacVirtualKey.rightBracket] = 0x30; t[MacVirtualKey.backslash] = 0x31; t[MacVirtualKey.semicolon] = 0x33; t[MacVirtualKey.quote] = 0x34
        t[MacVirtualKey.grave] = 0x35; t[MacVirtualKey.comma] = 0x36; t[MacVirtualKey.period] = 0x37; t[MacVirtualKey.slash] = 0x38
        t[MacVirtualKey.capsLock] = 0x39; t[MacVirtualKey.help] = 0x49; t[MacVirtualKey.home] = 0x4a; t[MacVirtualKey.pageUp] = 0x4b
        t[MacVirtualKey.forwardDelete] = 0x4c; t[MacVirtualKey.end] = 0x4d; t[MacVirtualKey.pageDown] = 0x4e
        t[MacVirtualKey.rightArrow] = 0x4f; t[MacVirtualKey.leftArrow] = 0x50; t[MacVirtualKey.downArrow] = 0x51; t[MacVirtualKey.upArrow] = 0x52
        t[MacVirtualKey.keypadClear] = 0x53; t[MacVirtualKey.keypadDivide] = 0x54; t[MacVirtualKey.keypadMultiply] = 0x55
        t[MacVirtualKey.keypadMinus] = 0x56; t[MacVirtualKey.keypadPlus] = 0x57; t[MacVirtualKey.keypadEnter] = 0x58
        t[MacVirtualKey.keypadDecimal] = 0x63; t[MacVirtualKey.keypadEquals] = 0x67
        t[MacVirtualKey.control] = 0xe0; t[MacVirtualKey.shift] = 0xe1; t[MacVirtualKey.option] = 0xe2; t[MacVirtualKey.command] = 0xe3
        t[MacVirtualKey.rightControl] = 0xe4; t[MacVirtualKey.rightShift] = 0xe5; t[MacVirtualKey.rightOption] = 0xe6; t[MacVirtualKey.rightCommand] = 0xe7
        return t
    }()

    // MARK: Lookups

    /// Android keycode for any mappable key (letters, digits, punctuation, specials).
    public static func androidKeycode(virtualKey: UInt16) -> Int32? {
        if let k = specialKeys[virtualKey] { return k }
        if let i = letters[virtualKey] { return AndroidInput.Keycode.letter(i) }
        if virtualKey == MacVirtualKey.space { return AndroidInput.Keycode.space }
        if let n = digits[virtualKey] { return AndroidInput.Keycode.digit(n) }
        if let k = punctuation[virtualKey] { return k }
        return nil
    }

    public static func hidUsage(virtualKey: UInt16) -> UInt8? {
        hidUsages[virtualKey]
    }

    public static func isModifier(virtualKey: UInt16) -> Bool {
        switch virtualKey {
        case MacVirtualKey.command, MacVirtualKey.rightCommand, MacVirtualKey.option, MacVirtualKey.rightOption,
             MacVirtualKey.control, MacVirtualKey.rightControl, MacVirtualKey.shift, MacVirtualKey.rightShift, MacVirtualKey.capsLock:
            return true
        default:
            return false
        }
    }

    public static func metaState(_ m: MacModifiers) -> AndroidInput.MetaState {
        var s: AndroidInput.MetaState = []
        if m.contains(.leftShift) { s.formUnion([.shiftOn, .shiftLeft]) }
        if m.contains(.rightShift) { s.formUnion([.shiftOn, .shiftRight]) }
        if m.contains(.leftControl) { s.formUnion([.ctrlOn, .ctrlLeft]) }
        if m.contains(.rightControl) { s.formUnion([.ctrlOn, .ctrlRight]) }
        if m.contains(.leftOption) { s.formUnion([.altOn, .altLeft]) }
        if m.contains(.rightOption) { s.formUnion([.altOn, .altRight]) }
        if m.contains(.leftCommand) { s.formUnion([.metaOn, .metaLeft]) }
        if m.contains(.rightCommand) { s.formUnion([.metaOn, .metaRight]) }
        if m.contains(.capsLock) { s.insert(.capsLock) }
        return s
    }

    public static func hidModifiers(_ m: MacModifiers) -> HidKeyboard.Modifiers {
        var h: HidKeyboard.Modifiers = []
        if m.contains(.leftShift) { h.insert(.leftShift) }
        if m.contains(.rightShift) { h.insert(.rightShift) }
        if m.contains(.leftControl) { h.insert(.leftControl) }
        if m.contains(.rightControl) { h.insert(.rightControl) }
        if m.contains(.leftOption) { h.insert(.leftAlt) }
        if m.contains(.rightOption) { h.insert(.rightAlt) }
        if m.contains(.leftCommand) { h.insert(.leftGui) }
        if m.contains(.rightCommand) { h.insert(.rightGui) }
        return h
    }

    /// SDK mixed mode (scrcpy default): special keys, letters and space go as keycodes (layout-independent on
    /// Android's side, `metaState` carries Shift); anything printable goes as text unless ⌘/⌃ is held, so
    /// accents, dead keys and IME output arrive verbatim.
    public static func decide(virtualKey: UInt16, characters: String?, modifiers: MacModifiers) -> Decision {
        if let k = specialKeys[virtualKey] { return .keycode(k) }
        let shortcut = modifiers.hasCommand || modifiers.hasControl
        let text = characters ?? ""
        let plainAscii = text.count == 1 && text.unicodeScalars.first.map { $0.isASCII && !($0.value < 0x20) } == true
        if let i = letters[virtualKey] {
            if shortcut || plainAscii || text.isEmpty { return .keycode(AndroidInput.Keycode.letter(i)) }
            return .text(text)
        }
        if virtualKey == MacVirtualKey.space {
            if shortcut || plainAscii || text.isEmpty { return .keycode(AndroidInput.Keycode.space) }
            return .text(text)
        }
        if shortcut {
            if let n = digits[virtualKey] { return .keycode(AndroidInput.Keycode.digit(n)) }
            if let k = punctuation[virtualKey] { return .keycode(k) }
            return .ignore
        }
        if text.isEmpty { return .ignore }
        // Control characters (e.g. ⌃-combos on non-ANSI layouts) carry no printable text.
        if text.unicodeScalars.allSatisfy({ $0.value < 0x20 || $0.value == 0x7f }) { return .ignore }
        return .text(text)
    }
}

extension ControlMessage {
    /// Splits text into chunks of at most `maxTextBytes` UTF-8 bytes on character boundaries.
    public static func textChunks(_ text: String, maxBytes: Int = maxTextBytes) -> [String] {
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for ch in text {
            let n = ch.utf8.count
            if currentBytes + n > maxBytes, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(ch)
            currentBytes += n
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
