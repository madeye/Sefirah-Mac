import Foundation

/// Client → server messages (`S/control/ControlMessageReader.java`); `encode()` is the wire form.
public enum ControlMessage: Equatable, Sendable {
    case injectKeycode(action: AndroidInput.KeyAction, keycode: Int32, repeat: UInt32, metaState: AndroidInput.MetaState)
    case injectText(String)
    case injectTouch(action: AndroidInput.MotionAction, pointerId: UInt64, x: Int32, y: Int32, screenWidth: UInt16, screenHeight: UInt16,
                     pressure: Float, actionButton: AndroidInput.Buttons, buttons: AndroidInput.Buttons)
    case injectScroll(x: Int32, y: Int32, screenWidth: UInt16, screenHeight: UInt16, hscroll: Float, vscroll: Float, buttons: AndroidInput.Buttons)
    case backOrScreenOn(AndroidInput.KeyAction)
    case expandNotificationPanel
    case expandSettingsPanel
    case collapsePanels
    case getClipboard(AndroidInput.CopyKey)
    case setClipboard(sequence: UInt64, paste: Bool, text: String)
    case setDisplayPower(on: Bool)
    case rotateDevice
    case uhidCreate(id: UInt16, vendorId: UInt16, productId: UInt16, name: String, descriptor: Data)
    case uhidInput(id: UInt16, data: Data)
    case uhidDestroy(id: UInt16)
    case openHardKeyboardSettings
    case startApp(String)
    case resetVideo
    case resizeDisplay(width: UInt16, height: UInt16)
    case scanFile(String)

    public static let maxTextBytes = 300
    public static let maxClipboardBytes = 262_130

    public var type: UInt8 {
        switch self {
        case .injectKeycode: return 0
        case .injectText: return 1
        case .injectTouch: return 2
        case .injectScroll: return 3
        case .backOrScreenOn: return 4
        case .expandNotificationPanel: return 5
        case .expandSettingsPanel: return 6
        case .collapsePanels: return 7
        case .getClipboard: return 8
        case .setClipboard: return 9
        case .setDisplayPower: return 10
        case .rotateDevice: return 11
        case .uhidCreate: return 12
        case .uhidInput: return 13
        case .uhidDestroy: return 14
        case .openHardKeyboardSettings: return 15
        case .startApp: return 16
        case .resetVideo: return 17
        case .resizeDisplay: return 21
        case .scanFile: return 22
        }
    }

    /// Messages that may be dropped when the send queue overflows (input events); never UHID create/destroy.
    public var isDroppable: Bool {
        switch self {
        case .injectTouch, .injectScroll, .injectText, .injectKeycode, .uhidInput: return true
        default: return false
        }
    }

    public func encode() -> Data {
        var d = Data([type])
        switch self {
        case .injectKeycode(let action, let keycode, let rep, let meta):
            d.append(action.rawValue)
            BigEndian.append(keycode, to: &d)
            BigEndian.append(rep, to: &d)
            BigEndian.append(meta.rawValue, to: &d)
        case .injectText(let text):
            let bytes = Data(text.utf8.prefix(Self.maxTextBytes))
            BigEndian.append(UInt32(bytes.count), to: &d)
            d.append(bytes)
        case .injectTouch(let action, let pointerId, let x, let y, let w, let h, let pressure, let actionButton, let buttons):
            d.append(action.rawValue)
            BigEndian.append(pointerId, to: &d)
            BigEndian.append(x, to: &d)
            BigEndian.append(y, to: &d)
            BigEndian.append(w, to: &d)
            BigEndian.append(h, to: &d)
            BigEndian.append(Self.u16FixedPoint(pressure), to: &d)
            BigEndian.append(actionButton.rawValue, to: &d)
            BigEndian.append(buttons.rawValue, to: &d)
        case .injectScroll(let x, let y, let w, let h, let hscroll, let vscroll, let buttons):
            BigEndian.append(x, to: &d)
            BigEndian.append(y, to: &d)
            BigEndian.append(w, to: &d)
            BigEndian.append(h, to: &d)
            BigEndian.append(Self.i16FixedPoint(hscroll / 16), to: &d)
            BigEndian.append(Self.i16FixedPoint(vscroll / 16), to: &d)
            BigEndian.append(buttons.rawValue, to: &d)
        case .backOrScreenOn(let action):
            d.append(action.rawValue)
        case .expandNotificationPanel, .expandSettingsPanel, .collapsePanels, .rotateDevice, .openHardKeyboardSettings, .resetVideo:
            break
        case .getClipboard(let key):
            d.append(key.rawValue)
        case .setClipboard(let sequence, let paste, let text):
            let bytes = Data(text.utf8.prefix(Self.maxClipboardBytes))
            BigEndian.append(sequence, to: &d)
            d.append(paste ? 1 : 0)
            BigEndian.append(UInt32(bytes.count), to: &d)
            d.append(bytes)
        case .setDisplayPower(let on):
            d.append(on ? 1 : 0)
        case .uhidCreate(let id, let vendor, let product, let name, let descriptor):
            BigEndian.append(id, to: &d)
            BigEndian.append(vendor, to: &d)
            BigEndian.append(product, to: &d)
            let nameBytes = Data(name.utf8.prefix(255))
            d.append(UInt8(nameBytes.count))
            d.append(nameBytes)
            BigEndian.append(UInt16(descriptor.count), to: &d)
            d.append(descriptor)
        case .uhidInput(let id, let data):
            BigEndian.append(id, to: &d)
            BigEndian.append(UInt16(data.count), to: &d)
            d.append(data)
        case .uhidDestroy(let id):
            BigEndian.append(id, to: &d)
        case .startApp(let name):
            let bytes = Data(name.utf8.prefix(255))
            d.append(UInt8(bytes.count))
            d.append(bytes)
        case .resizeDisplay(let w, let h):
            BigEndian.append(w, to: &d)
            BigEndian.append(h, to: &d)
        case .scanFile(let path):
            let bytes = Data(path.utf8)
            BigEndian.append(UInt32(bytes.count), to: &d)
            d.append(bytes)
        }
        return d
    }

    /// `f == 1.0 ? 0xffff : UInt16(f * 65536)` (server maps 0xffff → 1.0).
    public static func u16FixedPoint(_ f: Float) -> UInt16 {
        let clamped = max(0, min(1, f))
        if clamped >= 1 { return 0xffff }
        return UInt16(clamped * 65536)
    }

    /// `n == 1.0 ? 0x7fff : Int16(n * 32768)` for `n` in [-1, 1].
    public static func i16FixedPoint(_ f: Float) -> Int16 {
        let clamped = max(-1, min(1, f))
        if clamped >= 1 { return 0x7fff }
        return Int16(clamped * 32768)
    }
}
