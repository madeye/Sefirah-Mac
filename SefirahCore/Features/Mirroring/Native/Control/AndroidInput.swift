import Foundation

/// Android input constants used by the control protocol (`android.view.MotionEvent` / `KeyEvent`).
public enum AndroidInput {
    public enum MotionAction: UInt8, Sendable { case down = 0, up = 1, move = 2, cancel = 3, hoverMove = 7 }
    public enum KeyAction: UInt8, Sendable { case down = 0, up = 1 }
    public enum CopyKey: UInt8, Sendable { case none = 0, copy = 1, cut = 2 }

    public static let pointerMouse: UInt64 = 0xffff_ffff_ffff_ffff
    public static let pointerGenericFinger: UInt64 = 0xffff_ffff_ffff_fffe
    public static let pointerVirtualFinger: UInt64 = 0xffff_ffff_ffff_fffd

    public struct Buttons: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }
        public static let primary = Buttons(rawValue: 1)
        public static let secondary = Buttons(rawValue: 2)
        public static let tertiary = Buttons(rawValue: 4)
        public static let back = Buttons(rawValue: 8)
        public static let forward = Buttons(rawValue: 16)
    }

    public struct MetaState: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }
        public static let shiftOn = MetaState(rawValue: 0x1)
        public static let altOn = MetaState(rawValue: 0x2)
        public static let symOn = MetaState(rawValue: 0x4)
        public static let altLeft = MetaState(rawValue: 0x10)
        public static let altRight = MetaState(rawValue: 0x20)
        public static let shiftLeft = MetaState(rawValue: 0x40)
        public static let shiftRight = MetaState(rawValue: 0x80)
        public static let ctrlOn = MetaState(rawValue: 0x1000)
        public static let ctrlLeft = MetaState(rawValue: 0x2000)
        public static let ctrlRight = MetaState(rawValue: 0x4000)
        public static let metaOn = MetaState(rawValue: 0x10000)
        public static let metaLeft = MetaState(rawValue: 0x20000)
        public static let metaRight = MetaState(rawValue: 0x40000)
        public static let capsLock = MetaState(rawValue: 0x100000)
        public static let numLock = MetaState(rawValue: 0x200000)
        public static let scrollLock = MetaState(rawValue: 0x400000)
    }

    /// `android.view.KeyEvent` keycodes used by the toolbar and keyboard mapping.
    public enum Keycode {
        public static let home: Int32 = 3
        public static let back: Int32 = 4
        public static let digit0: Int32 = 7 // 0–9 → 7–16
        public static let dpadUp: Int32 = 19
        public static let dpadDown: Int32 = 20
        public static let dpadLeft: Int32 = 21
        public static let dpadRight: Int32 = 22
        public static let volumeUp: Int32 = 24
        public static let volumeDown: Int32 = 25
        public static let power: Int32 = 26
        public static let a: Int32 = 29 // A–Z → 29–54
        public static let comma: Int32 = 55
        public static let period: Int32 = 56
        public static let altLeft: Int32 = 57
        public static let altRight: Int32 = 58
        public static let shiftLeft: Int32 = 59
        public static let shiftRight: Int32 = 60
        public static let tab: Int32 = 61
        public static let space: Int32 = 62
        public static let enter: Int32 = 66
        public static let del: Int32 = 67
        public static let grave: Int32 = 68
        public static let minus: Int32 = 69
        public static let equals: Int32 = 70
        public static let leftBracket: Int32 = 71
        public static let rightBracket: Int32 = 72
        public static let backslash: Int32 = 73
        public static let semicolon: Int32 = 74
        public static let apostrophe: Int32 = 75
        public static let slash: Int32 = 76
        public static let menu: Int32 = 82
        public static let pageUp: Int32 = 92
        public static let pageDown: Int32 = 93
        public static let escape: Int32 = 111
        public static let forwardDel: Int32 = 112
        public static let ctrlLeft: Int32 = 113
        public static let ctrlRight: Int32 = 114
        public static let capsLock: Int32 = 115
        public static let metaLeft: Int32 = 117
        public static let metaRight: Int32 = 118
        public static let moveHome: Int32 = 122
        public static let moveEnd: Int32 = 123
        public static let insert: Int32 = 124
        public static let f1: Int32 = 131 // F1–F12 → 131–142
        public static let numLock: Int32 = 143
        public static let numpad0: Int32 = 144 // NUMPAD_0–9 → 144–153
        public static let numpadDivide: Int32 = 154
        public static let numpadMultiply: Int32 = 155
        public static let numpadSubtract: Int32 = 156
        public static let numpadAdd: Int32 = 157
        public static let numpadDot: Int32 = 158
        public static let numpadEnter: Int32 = 160
        public static let numpadEquals: Int32 = 161
        public static let volumeMute: Int32 = 164
        public static let appSwitch: Int32 = 187
        public static let cut: Int32 = 277
        public static let copy: Int32 = 278
        public static let paste: Int32 = 279
        public static let allApps: Int32 = 284

        public static func letter(_ index: Int) -> Int32 { a + Int32(index) } // 0 = A
        public static func digit(_ n: Int) -> Int32 { digit0 + Int32(n) }
        public static func function(_ n: Int) -> Int32 { f1 + Int32(n - 1) } // F1 = 1
        public static func numpad(_ n: Int) -> Int32 { numpad0 + Int32(n) }
    }
}
