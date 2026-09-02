import AppKit
import SefirahCore
import SwiftUI

/// Streaming-state toolbar: navigation keys and device commands sent over the control socket.
struct MirrorToolbar: View {
    let controller: MirrorController
    @State private var showInputHelp = false

    var body: some View {
        HStack(spacing: 6) {
            Text(controller.deviceModel.map { "\(controller.title) · \($0)" } ?? controller.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            key("Back", "chevron.backward", AndroidInput.Keycode.back)
            key("Home", "circle", AndroidInput.Keycode.home)
            key("Recents", "square.on.square", AndroidInput.Keycode.appSwitch)
            action("Rotate", "rotate.right") { controller.send(.rotateDevice) }
            action(controller.displayOn ? "Screen off" : "Screen on", controller.displayOn ? "sun.min" : "sun.max") {
                controller.toggleDisplayPower()
            }
            action("Notifications", "bell") { controller.send(.expandNotificationPanel) }
            if controller.config?.options.audio ?? false {
                action(controller.isMuted ? "Unmute" : "Mute", controller.isMuted ? "speaker.slash" : "speaker.wave.2") {
                    controller.toggleMute()
                }
                .disabled(controller.audioUnavailable)
            }
            key("Volume down", "speaker.minus", AndroidInput.Keycode.volumeDown)
            key("Volume up", "speaker.plus", AndroidInput.Keycode.volumeUp)
            key("Power", "power", AndroidInput.Keycode.power)
            action("Fullscreen", "arrow.up.left.and.arrow.down.right") { NSApp.keyWindow?.toggleFullScreen(nil) }
            Button {
                showInputHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Input not working?")
            .popover(isPresented: $showInputHelp, arrowEdge: .bottom) { inputHelp }
            Divider().frame(height: 16)
            if controller.state == .stopping {
                ProgressView().controlSize(.small)
            }
            Button("Stop") { controller.stop() }
                .disabled(controller.state == .stopping)
        }
        .buttonStyle(.borderless)
        .disabled(controller.state != .streaming && controller.state != .stopping)
    }

    private func key(_ title: String, _ symbol: String, _ keycode: Int32) -> some View {
        action(title, symbol) { controller.pressKey(keycode) }
    }

    private func action(_ title: String, _ symbol: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol) }
            .help(title)
            .accessibilityLabel(title)
    }

    private var inputHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input not working?").font(.headline)
            Text("Touches and keys are injected by scrcpy-server through ADB. Some phones block this until an extra developer option is enabled:")
            Text("• Xiaomi / HyperOS: Developer options ▸ USB debugging (Security settings). A Xiaomi account and SIM may be required.")
            Text("• Others: check that “USB debugging” stays enabled and that no MDM/security app restricts input injection.")
            Text("The mirror keeps working read-only; toolbar keys, screen off and clipboard sync are unaffected.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding()
        .frame(width: 360)
    }
}
