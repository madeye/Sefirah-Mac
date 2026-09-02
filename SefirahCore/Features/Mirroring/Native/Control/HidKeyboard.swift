import Foundation

/// UHID keyboard (scrcpy `app/src/hid/hid_keyboard.c`): report descriptor and 8-byte input reports.
public enum HidKeyboard {
    public static let deviceId: UInt16 = 1
    public static let maxKeys = 6
    public static let reportSize = 8
    /// Six bytes of `ErrorRollOver` when more than six keys are held.
    public static let errorRollOver: UInt8 = 0x01

    /// 63 bytes: Generic Desktop / Keyboard, 8 modifier bits, 1 reserved byte, 5 LED bits + 3 padding, 6 key usages.
    public static let descriptor = Data([
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
        0x75, 0x08, 0x95, 0x01, 0x81, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x75, 0x01, 0x95, 0x05, 0x91, 0x02, 0x75, 0x03, 0x95, 0x01,
        0x91, 0x01, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x15, 0x00, 0x25, 0x65, 0x75, 0x08, 0x95, 0x06, 0x81, 0x00, 0xC0,
    ])

    public struct Modifiers: OptionSet, Sendable, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let leftControl = Modifiers(rawValue: 0x01)
        public static let leftShift = Modifiers(rawValue: 0x02)
        public static let leftAlt = Modifiers(rawValue: 0x04)
        public static let leftGui = Modifiers(rawValue: 0x08)
        public static let rightControl = Modifiers(rawValue: 0x10)
        public static let rightShift = Modifiers(rawValue: 0x20)
        public static let rightAlt = Modifiers(rawValue: 0x40)
        public static let rightGui = Modifiers(rawValue: 0x80)
    }

    /// LED output report bits (`uhidOutput` data byte 0).
    public struct Leds: OptionSet, Sendable, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let numLock = Leds(rawValue: 0x01)
        public static let capsLock = Leds(rawValue: 0x02)
    }

    /// `[mods][00][k1..k6]`; `keys` are usage-page-7 ids in press order. More than six → phantom state.
    public static func report(modifiers: Modifiers, keys: [UInt8]) -> Data {
        var d = Data(count: reportSize)
        d[0] = modifiers.rawValue
        if keys.count > maxKeys {
            for i in 0..<maxKeys { d[2 + i] = errorRollOver }
        } else {
            for (i, key) in keys.enumerated() { d[2 + i] = key }
        }
        return d
    }

    public static var createMessage: ControlMessage {
        .uhidCreate(id: deviceId, vendorId: 0, productId: 0, name: "", descriptor: descriptor)
    }
}
