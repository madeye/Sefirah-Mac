import AppKit
import SefirahCore
import SwiftUI

struct MirrorView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let device = model.selectedDevice {
                let sessions = model.mirrorSessions(for: device.id)
                if let controller = model.displayedMirrorController {
                    VStack(spacing: 0) {
                        if sessions.count > 1 {
                            sessionSelector(sessions, current: controller)
                            Divider()
                        }
                        sessionBody(controller, device: device)
                    }
                } else {
                    emptyState(device)
                }
            } else {
                ContentUnavailableView("No device", systemImage: "iphone.slash", description: Text("Pair a phone to mirror its screen."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - States

    /// Device mirror + per-app virtual-display sessions of the selected phone.
    private func sessionSelector(_ sessions: [MirrorController], current: MirrorController) -> some View {
        Picker("Session", selection: Binding(
            get: { current.key },
            set: { model.focusedMirrorKey = $0 }
        )) {
            ForEach(sessions, id: \.key) { session in
                Text(session.package == nil ? "Screen" : session.title).tag(session.key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func emptyState(_ device: ConnectedPeer) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Mirror \(device.name)").font(.title3.weight(.semibold))
            Text(caption(for: device.id)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start mirroring") { model.startMirror() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canMirror || model.isMirrorPending(device.id))
                Button("Launch an app…") { model.selectedTab = .apps }
            }
            if !model.canMirror {
                Text("Bundled adb / scrcpy-server missing. Reinstall Sefirah or switch the backend in Settings.")
                    .font(.caption).foregroundStyle(.red)
            }
            if model.general.mirrorBackend == .external {
                Text("Backend is set to external scrcpy; the stream opens in a separate window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func sessionBody(_ controller: MirrorController, device: ConnectedPeer) -> some View {
        switch controller.state {
        case .preparing(let stage):
            progress(stage.description, controller: controller)
        case .connecting:
            progress("Connecting…", controller: controller)
        case .streaming, .stopping:
            streaming(controller)
        case .failed(let error):
            if controller.reconnecting {
                progress("Connection lost — reconnecting…", controller: controller)
            } else {
                failed(error, controller: controller)
            }
        case .idle:
            emptyState(device)
        }
    }

    private func progress(_ text: String, controller: MirrorController) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
            Button("Cancel") { controller.stop() }
        }
        .padding()
    }

    private func streaming(_ controller: MirrorController) -> some View {
        VStack(spacing: 0) {
            MirrorToolbar(controller: controller)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            ZStack {
                Color.black
                if let ratio = controller.aspectRatio {
                    MirrorSurfaceView(displayLayer: controller.layer, input: controller.input)
                        .aspectRatio(ratio, contentMode: .fit)
                } else {
                    MirrorSurfaceView(displayLayer: controller.layer, input: controller.input)
                }
                if !controller.displayOn, controller.package == nil {
                    // The server keeps streaming (black) frames while the phone display is off
                    // (device sessions only: the power action never affects a virtual display).
                    VStack(spacing: 6) {
                        Image(systemName: "moon.zzz").font(.title2)
                        Text("Phone screen is off").font(.callout)
                        Text("The stream continues; touch and keys still work.").font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(14)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !controller.warnings.isEmpty || controller.clipboardBanner != nil {
                Divider()
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(1)
                        }
                        if let clip = controller.clipboardBanner {
                            Label("Clipboard from phone: \(clip)", systemImage: "doc.on.clipboard").font(.caption).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Dismiss") { controller.dismissWarnings() }.controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 12) {
                Text(footer(controller)).font(.caption).foregroundStyle(.secondary)
                if controller.preferences.physicalKeyboard {
                    Text(controller.capsLockOn ? "CAPS" : "caps").font(.caption2.monospaced()).foregroundStyle(controller.capsLockOn ? .primary : .tertiary)
                }
                Spacer()
                if controller.audioUnavailable {
                    Label("No audio", systemImage: "speaker.slash").font(.caption).foregroundStyle(.secondary)
                        .help("The phone reported that audio capture is unavailable (Android < 11, or the audio source is unsupported).")
                } else if controller.isMuted {
                    Label("Muted", systemImage: "speaker.slash").font(.caption).foregroundStyle(.secondary)
                }
                if let last = controller.serverErrors.last {
                    Text(last).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func failed(_ error: MirrorError, controller: MirrorController) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
            Text(error.title).font(.headline).multilineTextAlignment(.center)
            if let hint = MirrorDiagnostics.hint(error) {
                Text(hint).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack {
                Button("Retry") {
                    controller.stop()
                    model.startMirror(package: controller.package, appName: controller.package == nil ? nil : controller.title)
                }
                Button("Dismiss") { controller.stop() }
                Button("Use external scrcpy") {
                    controller.stop()
                    model.launchScrcpy(package: controller.package, appName: controller.package == nil ? nil : controller.title)
                }
                .disabled(!model.canUseExternalScrcpy)
                Button("Copy log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText(error, controller: controller), forType: .string)
                }
            }
        }
        .padding()
        .frame(maxWidth: 520)
    }

    // MARK: - Helpers

    private func caption(for deviceId: String) -> String {
        let settings = model.deviceSettings(for: deviceId)
        let codec = settings.videoCodec == 1 ? "H.265" : settings.videoCodec == 2 ? "AV1" : "H.264"
        let size = settings.videoResolution.trimmingCharacters(in: .whitespaces)
        let bitrate = settings.videoBitrate.trimmingCharacters(in: .whitespaces)
        return "\(codec) · \(size.isEmpty ? "native size" : "max \(size) px") · \(bitrate.isEmpty ? "8M" : bitrate)bps"
    }

    private func footer(_ controller: MirrorController) -> String {
        var parts: [String] = []
        if let codec = controller.codec { parts.append(codec.displayName) }
        if let size = controller.videoSize { parts.append("\(Int(size.width))×\(Int(size.height))") }
        if let options = controller.config?.options { parts.append("\(options.videoBitRate / 1_000_000) Mbps") }
        if let audio = controller.audioCodec { parts.append(audio.displayName) }
        return parts.joined(separator: " · ")
    }

    private func logText(_ error: MirrorError, controller: MirrorController) -> String {
        var text = "Sefirah native mirror failed: \(error.title)\n"
        if case .serverExited(_, let log) = error { text += log + "\n" }
        text += controller.logTail
        return text
    }
}
