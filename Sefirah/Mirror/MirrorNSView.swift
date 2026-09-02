import AppKit
import AVFoundation
import SefirahCore

/// Layer-hosting view for the session's `AVSampleBufferDisplayLayer`; captures mouse/keyboard input
/// and forwards raw facts to the controller's `MirrorInputHandler`.
final class MirrorNSView: NSView {
    weak var input: MirrorInputHandler?
    private var trackingArea: NSTrackingArea?

    init(displayLayer: AVSampleBufferDisplayLayer) {
        super.init(frame: .zero)
        layer = displayLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        reportSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        reportSize()
    }

    private func reportSize() {
        let scale = window?.backingScaleFactor ?? 2
        input?.viewResized(pixels: CGSize(width: bounds.width * scale, height: bounds.height * scale))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Mouse

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        input?.mouseDown(button: .primary, at: point(event), viewSize: bounds.size, modifiers: MacModifiers(flags: event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        input?.mouseDragged(button: .primary, at: point(event), viewSize: bounds.size)
    }

    override func mouseUp(with event: NSEvent) {
        input?.mouseUp(button: .primary, at: point(event), viewSize: bounds.size)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        input?.mouseDown(button: .secondary, at: point(event), viewSize: bounds.size, modifiers: MacModifiers(flags: event.modifierFlags))
    }

    override func rightMouseUp(with event: NSEvent) {
        input?.mouseUp(button: .secondary, at: point(event), viewSize: bounds.size)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        input?.mouseDown(button: .tertiary, at: point(event), viewSize: bounds.size, modifiers: MacModifiers(flags: event.modifierFlags))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        input?.mouseUp(button: .tertiary, at: point(event), viewSize: bounds.size)
    }

    override func mouseMoved(with event: NSEvent) {
        input?.mouseMoved(at: point(event), viewSize: bounds.size)
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        input?.scroll(at: point(event), viewSize: bounds.size,
                      deltaX: precise ? event.scrollingDeltaX : event.deltaX,
                      deltaY: precise ? event.scrollingDeltaY : event.deltaY,
                      precise: precise)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        input?.keyDown(virtualKey: event.keyCode, characters: event.characters, modifiers: MacModifiers(flags: event.modifierFlags), isRepeat: event.isARepeat)
    }

    override func keyUp(with event: NSEvent) {
        input?.keyUp(virtualKey: event.keyCode, modifiers: MacModifiers(flags: event.modifierFlags))
    }

    override func flagsChanged(with event: NSEvent) {
        input?.flagsChanged(modifiers: MacModifiers(flags: event.modifierFlags))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        if input?.keyEquivalent(virtualKey: event.keyCode, modifiers: MacModifiers(flags: event.modifierFlags)) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
