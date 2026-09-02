import AppKit
import Foundation
import SefirahCore

/// Turns raw AppKit facts (points, buttons, virtual keys, modifier flags) into control messages.
/// Owned by `MirrorController`; `MirrorNSView` calls it directly (both are main-actor).
@MainActor
final class MirrorInputHandler {
    enum KeyboardMode { case sdk, uhid }

    /// Flip if device testing shows the wheel direction is reversed.
    static let invertScroll = false
    /// Precise (trackpad) deltas are points; ~10 points per notch.
    static let pointsPerNotch: CGFloat = 10
    static let flexResizeDebounce: UInt64 = 100_000_000

    var send: (ControlMessage) -> Void = { _ in }
    var currentVideoSize: () -> (width: Int, height: Int)? = { nil }
    var pasteboardText: () -> String? = { NSPasteboard.general.string(forType: .string) }
    var keyboardMode: KeyboardMode = .sdk
    var forwardHover = false
    var flexDisplay = false
    var maxSize = 0

    private(set) var buttons: AndroidInput.Buttons = []
    private var dragSize: (width: Int, height: Int)?
    private var pinching = false
    private var modifiers = MacModifiers()
    private var pressedKeycodes: [UInt16: Int32] = [:]
    private var hidKeys: [UInt8] = []
    private var resizeTask: Task<Void, Never>?
    private var lastResize: (Int, Int)?

    func reset() {
        buttons = []
        dragSize = nil
        pinching = false
        pressedKeycodes = [:]
        hidKeys = []
        resizeTask?.cancel()
        resizeTask = nil
        lastResize = nil
    }

    // MARK: - Mouse

    func mouseDown(button: AndroidInput.Buttons, at point: CGPoint, viewSize: CGSize, modifiers: MacModifiers) {
        self.modifiers = modifiers
        switch button {
        case .primary:
            guard let size = currentVideoSize() else { return }
            dragSize = size
            buttons.insert(.primary)
            pinching = modifiers.hasOption
            touch(.down, point: point, viewSize: viewSize, pressure: 1, actionButton: .primary)
        case .secondary:
            send(.backOrScreenOn(.down))
        case .tertiary:
            send(.injectKeycode(action: .down, keycode: AndroidInput.Keycode.home, repeat: 0, metaState: []))
        default:
            break
        }
    }

    func mouseDragged(button: AndroidInput.Buttons, at point: CGPoint, viewSize: CGSize) {
        guard button == .primary, buttons.contains(.primary) else { return }
        touch(.move, point: point, viewSize: viewSize, pressure: 1, actionButton: [])
    }

    func mouseUp(button: AndroidInput.Buttons, at point: CGPoint, viewSize: CGSize) {
        switch button {
        case .primary:
            guard buttons.contains(.primary) else { return }
            buttons.remove(.primary)
            touch(.up, point: point, viewSize: viewSize, pressure: 0, actionButton: .primary)
            dragSize = nil
            pinching = false
        case .secondary:
            send(.backOrScreenOn(.up))
        case .tertiary:
            send(.injectKeycode(action: .up, keycode: AndroidInput.Keycode.home, repeat: 0, metaState: []))
        default:
            break
        }
    }

    func mouseMoved(at point: CGPoint, viewSize: CGSize) {
        guard forwardHover, buttons.isEmpty, let size = currentVideoSize() else { return }
        let mapper = PointerMapper(viewSize: viewSize, videoSize: CGSize(width: size.width, height: size.height))
        guard let f = mapper.toFrame(point) else { return }
        send(.injectTouch(action: .hoverMove, pointerId: AndroidInput.pointerMouse, x: f.x, y: f.y,
                          screenWidth: UInt16(size.width), screenHeight: UInt16(size.height), pressure: 0, actionButton: [], buttons: []))
    }

    private func touch(_ action: AndroidInput.MotionAction, point: CGPoint, viewSize: CGSize, pressure: Float, actionButton: AndroidInput.Buttons) {
        guard let size = dragSize else { return }
        if let now = currentVideoSize(), now.width != size.width || now.height != size.height {
            // The frame changed under the drag: the server would drop mismatched sizes, so end the gesture locally.
            buttons.remove(.primary)
            dragSize = nil
            pinching = false
            return
        }
        let mapper = PointerMapper(viewSize: viewSize, videoSize: CGSize(width: size.width, height: size.height))
        guard let f = mapper.toFrame(point, clamp: action != .down) else {
            if action == .down { buttons.remove(.primary); dragSize = nil; pinching = false }
            return
        }
        let w = UInt16(clamping: size.width), h = UInt16(clamping: size.height)
        send(.injectTouch(action: action, pointerId: AndroidInput.pointerMouse, x: f.x, y: f.y, screenWidth: w, screenHeight: h,
                          pressure: pressure, actionButton: actionButton, buttons: buttons))
        if pinching {
            let m = PointerMapper.mirrored(f, in: CGSize(width: size.width, height: size.height))
            send(.injectTouch(action: action, pointerId: AndroidInput.pointerVirtualFinger, x: m.x, y: m.y, screenWidth: w, screenHeight: h,
                              pressure: pressure, actionButton: [], buttons: []))
        }
    }

    // MARK: - Scroll

    func scroll(at point: CGPoint, viewSize: CGSize, deltaX: CGFloat, deltaY: CGFloat, precise: Bool) {
        guard let size = currentVideoSize() else { return }
        let mapper = PointerMapper(viewSize: viewSize, videoSize: CGSize(width: size.width, height: size.height))
        guard let f = mapper.toFrame(point) else { return }
        var h = precise ? deltaX / Self.pointsPerNotch : deltaX
        var v = precise ? deltaY / Self.pointsPerNotch : deltaY
        if Self.invertScroll { h = -h; v = -v }
        h = max(-16, min(16, h))
        v = max(-16, min(16, v))
        guard h != 0 || v != 0 else { return }
        send(.injectScroll(x: f.x, y: f.y, screenWidth: UInt16(clamping: size.width), screenHeight: UInt16(clamping: size.height),
                           hscroll: Float(h), vscroll: Float(v), buttons: buttons))
    }

    // MARK: - Keyboard

    func keyDown(virtualKey: UInt16, characters: String?, modifiers: MacModifiers, isRepeat: Bool) {
        self.modifiers = modifiers
        switch keyboardMode {
        case .uhid:
            guard let usage = MacKeyMap.hidUsage(virtualKey: virtualKey) else { return }
            if isRepeat { return } // Android generates repeats for HID keyboards.
            if !hidKeys.contains(usage) { hidKeys.append(usage) }
            sendHidReport()
        case .sdk:
            let meta = MacKeyMap.metaState(modifiers)
            switch MacKeyMap.decide(virtualKey: virtualKey, characters: characters, modifiers: modifiers) {
            case .keycode(let k):
                pressedKeycodes[virtualKey] = k
                send(.injectKeycode(action: .down, keycode: k, repeat: isRepeat ? 1 : 0, metaState: meta))
            case .text(let text):
                pressedKeycodes[virtualKey] = nil
                injectText(text)
            case .ignore:
                pressedKeycodes[virtualKey] = nil
            }
        }
    }

    func keyUp(virtualKey: UInt16, modifiers: MacModifiers) {
        self.modifiers = modifiers
        switch keyboardMode {
        case .uhid:
            guard let usage = MacKeyMap.hidUsage(virtualKey: virtualKey) else { return }
            hidKeys.removeAll { $0 == usage }
            sendHidReport()
        case .sdk:
            guard let k = pressedKeycodes.removeValue(forKey: virtualKey) else { return }
            send(.injectKeycode(action: .up, keycode: k, repeat: 0, metaState: MacKeyMap.metaState(modifiers)))
        }
    }

    /// Diffs modifier state; emits a modifier keycode per changed side (SDK) or a fresh HID report (UHID).
    func flagsChanged(modifiers new: MacModifiers) {
        let old = modifiers
        modifiers = new
        switch keyboardMode {
        case .uhid:
            sendHidReport()
        case .sdk:
            let pairs: [(MacModifiers, Int32)] = [
                (.leftShift, AndroidInput.Keycode.shiftLeft), (.rightShift, AndroidInput.Keycode.shiftRight),
                (.leftControl, AndroidInput.Keycode.ctrlLeft), (.rightControl, AndroidInput.Keycode.ctrlRight),
                (.leftOption, AndroidInput.Keycode.altLeft), (.rightOption, AndroidInput.Keycode.altRight),
                (.leftCommand, AndroidInput.Keycode.metaLeft), (.rightCommand, AndroidInput.Keycode.metaRight),
                (.capsLock, AndroidInput.Keycode.capsLock),
            ]
            for (flag, keycode) in pairs where old.contains(flag) != new.contains(flag) {
                let action: AndroidInput.KeyAction = new.contains(flag) ? .down : .up
                send(.injectKeycode(action: action, keycode: keycode, repeat: 0, metaState: MacKeyMap.metaState(new)))
            }
        }
    }

    /// ⌘ shortcuts owned by the mirror: returns false so the menu bar handles anything else.
    func keyEquivalent(virtualKey: UInt16, modifiers: MacModifiers) -> Bool {
        guard modifiers.hasCommand, !modifiers.hasControl, !modifiers.hasOption else { return false }
        switch virtualKey {
        case MacVirtualKey.v:
            guard let text = pasteboardText(), !text.isEmpty else { return true }
            if modifiers.hasShift {
                injectText(text)
            } else {
                send(.setClipboard(sequence: 0, paste: true, text: text))
            }
            return true
        case MacVirtualKey.c:
            send(.getClipboard(.copy))
            return true
        case MacVirtualKey.x:
            send(.getClipboard(.cut))
            return true
        case MacVirtualKey.a where !modifiers.hasShift:
            let ctrl: AndroidInput.MetaState = [.ctrlOn, .ctrlLeft]
            send(.injectKeycode(action: .down, keycode: AndroidInput.Keycode.a, repeat: 0, metaState: ctrl))
            send(.injectKeycode(action: .up, keycode: AndroidInput.Keycode.a, repeat: 0, metaState: ctrl))
            return true
        default:
            return false
        }
    }

    func injectText(_ text: String) {
        for chunk in ControlMessage.textChunks(text) { send(.injectText(chunk)) }
    }

    private func sendHidReport() {
        send(.uhidInput(id: HidKeyboard.deviceId, data: HidKeyboard.report(modifiers: MacKeyMap.hidModifiers(modifiers), keys: hidKeys)))
    }

    // MARK: - Flex display

    /// Surface size in backing pixels → debounced `RESIZE_DISPLAY` (larger side capped at `maxSize`).
    func viewResized(pixels: CGSize) {
        guard flexDisplay, pixels.width >= 1, pixels.height >= 1 else { return }
        var w = pixels.width, h = pixels.height
        if maxSize > 0 {
            let scale = CGFloat(maxSize) / max(w, h)
            if scale < 1 { w *= scale; h *= scale }
        }
        let target = (Int(w.rounded()) & ~1, Int(h.rounded()) & ~1)
        guard target.0 > 0, target.1 > 0, lastResize.map({ $0 != target }) ?? true else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.flexResizeDebounce)
            guard !Task.isCancelled, let self else { return }
            lastResize = target
            send(.resizeDisplay(width: UInt16(clamping: target.0), height: UInt16(clamping: target.1)))
        }
    }
}
