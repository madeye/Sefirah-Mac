import SefirahCore
import SwiftUI

/// Screen-mirroring settings (general backend options + the per-device scrcpy-server mapping).
/// Embedded in `SettingsView`'s "Screen mirroring" section; every change is saved immediately.
struct MirrorSettingsView: View {
    @Bindable var model: AppModel
    let deviceId: String?

    var body: some View {
        Picker("Backend", selection: $model.general.mirrorBackend) {
            Text("Native (in-app)").tag(MirrorBackend.native)
            Text("External scrcpy window").tag(MirrorBackend.external)
        }
        .onChange(of: model.general.mirrorBackend) { _, _ in model.saveGeneral() }
        Toggle("Fall back to external scrcpy when the native mirror fails", isOn: $model.general.mirrorFallbackToExternal)
            .onChange(of: model.general.mirrorFallbackToExternal) { _, _ in model.saveGeneral() }
            .disabled(!model.canUseExternalScrcpy)
        Toggle("Verbose scrcpy-server logs", isOn: $model.general.verboseMirrorLogs)
            .onChange(of: model.general.verboseMirrorLogs) { _, _ in model.saveGeneral() }

        if let deviceId {
            deviceSection(deviceId)
        } else {
            Text("Select a paired device to edit its mirroring options.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func deviceSection(_ id: String) -> some View {
        Toggle("Connect over Wi-Fi (ADB TCP/IP)", isOn: bind(id, \.adbTcpipModeEnabled))
        Toggle("Turn phone screen off while mirroring", isOn: bind(id, \.screenOff))
        Toggle("Physical keyboard (UHID)", isOn: bind(id, \.physicalKeyboard))
        Toggle("Sync clipboard automatically", isOn: bind(id, \.scrcpyClipboardAutosync))
        Toggle("Forward mouse hover", isOn: bind(id, \.forwardHover))

        DisclosureGroup("Video") {
            Picker("Codec", selection: bind(id, \.videoCodec)) {
                Text("H.264").tag(0)
                Text("H.265").tag(1)
                if VideoFormat.av1Supported { Text("AV1").tag(2) }
            }
            TextField("Max size (px, empty = native)", text: bind(id, \.videoResolution))
            TextField("Bit rate (e.g. 8M)", text: bind(id, \.videoBitrate))
            Stepper("Max frame rate: \(fps(id))", value: bind(id, \.frameRate), in: 0...120, step: 5)
            TextField("Crop (width:height:x:y)", text: bind(id, \.crop))
            TextField("Display id (0 = default)", text: bind(id, \.display))
            Stepper("Rotation angle: \(model.deviceSettings(for: id).rotationAngle)°", value: bind(id, \.rotationAngle), in: 0...270, step: 90)
            Toggle("Disable video (audio only)", isOn: bind(id, \.disableVideoForwarding))
        }
        DisclosureGroup("Audio") {
            Picker("Output", selection: bind(id, \.audioOutputMode)) {
                Text("Mac only").tag(AudioOutputModeType.desktop)
                Text("Mac and phone").tag(AudioOutputModeType.both)
                Text("Phone only (no audio stream)").tag(AudioOutputModeType.remote)
            }
            Picker("Codec", selection: bind(id, \.audioCodec)) {
                Text("Opus").tag(0)
                Text("AAC").tag(1)
                Text("Raw PCM").tag(2)
            }
            TextField("Bit rate (e.g. 128K)", text: bind(id, \.audioBitrate))
            Stepper("Buffer: \(latency(id)) ms", value: bind(id, \.audioBuffer), in: 0...500, step: 10)
            Toggle("Forward microphone instead of device audio", isOn: bind(id, \.forwardMicrophone))
        }
        DisclosureGroup("App launches (virtual display)") {
            Toggle("Open apps on a virtual display", isOn: bind(id, \.isVirtualDisplayEnabled))
            TextField("Virtual display size (WxH[/dpi], empty = phone size)", text: bind(id, \.virtualDisplaySize))
            Toggle("Flexible display (resize with the window)", isOn: bind(id, \.flexDisplay))
            Toggle("Run unlock commands before launching", isOn: bind(id, \.unlockDeviceBeforeLaunch))
            let commands = model.deviceSettings(for: id).unlockCommands.filter { !$0.command.trimmingCharacters(in: .whitespaces).isEmpty }
            Text(commands.isEmpty ? "No unlock commands configured." : "\(commands.count) adb shell command(s) run before the server is pushed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup("Custom server options") {
            TextField("key=value pairs (e.g. stay_awake=true show_touches=true)", text: bind(id, \.customArguments))
            Text("Native mirror: scrcpy-server key=value options. External backend: scrcpy CLI flags.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fps(_ id: String) -> String {
        let v = model.deviceSettings(for: id).frameRate
        return v > 0 ? "\(v)" : "unlimited"
    }

    private func latency(_ id: String) -> Int {
        let v = model.deviceSettings(for: id).audioBuffer
        return v > 0 ? v : 50
    }

    private func bind<T: Equatable>(_ deviceId: String, _ keyPath: WritableKeyPath<DeviceSettings, T>) -> Binding<T> {
        Binding(
            get: { model.deviceSettings(for: deviceId)[keyPath: keyPath] },
            set: { value in
                guard model.deviceSettings(for: deviceId)[keyPath: keyPath] != value else { return }
                model.updateDeviceSettings(for: deviceId) { $0[keyPath: keyPath] = value }
            }
        )
    }
}
