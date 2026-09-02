import SefirahCore
import SwiftUI

struct DeviceRailView: View {
    @Bindable var model: AppModel

    private let streamOrder: [AudioStreamType] = [.media, .ring, .notification, .alarm, .voiceCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let device = model.selectedDevice {
                deviceCard(device)
                if let battery = model.live.battery {
                    Label(
                        "\(battery.batteryLevel)%\(battery.isCharging ? " charging" : "")",
                        systemImage: battery.isCharging ? "battery.100.bolt" : "battery.100"
                    )
                }
                Picker("Ringer", selection: ringerBinding) {
                    Text("Silent").tag(0)
                    Text("Vibrate").tag(1)
                    Text("Ring").tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(!device.isConnected)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume").font(.caption).foregroundStyle(.secondary)
                    ForEach(streamOrder, id: \.self) { type in
                        StreamVolumeRow(
                            type: type,
                            level: model.live.audioStreams[type] ?? 0,
                            enabled: device.isConnected
                        ) { model.setAudioLevel(type, level: $0) }
                    }
                }

                HStack {
                    if model.isMirroring(device.id) {
                        Button("Stop") { model.stopMirrors(deviceId: device.id) }
                            .help("Stop every mirror session of this phone")
                    } else if model.isMirrorPending(device.id) {
                        Button("Mirror") {}
                            .disabled(true)
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Mirror") { model.startMirror() }
                            .disabled(!model.canMirror)
                            .help(model.canMirror ? "Mirror the phone screen" : "Bundled adb/scrcpy is missing. Reinstall Sefirah or set a custom scrcpy path in Settings.")
                    }
                    Button(model.live.soundPlaying ? "Stop sound" : "Find") {
                        model.toggleFindPhone()
                    }
                    Button(model.live.dndEnabled == true ? "DND On" : "DND") { model.toggleDnd() }
                }
                .controlSize(.small)
                HStack {
                    Button("Files") { model.openSftp() }
                    Button("Clipboard") { model.sendClipboard() }
                }
                .controlSize(.small)

                ForEach(model.live.playback, id: \.source) { session in
                    mediaCard(session, connected: device.isConnected)
                }
                NotificationFeedView(model: model)
            } else {
                Text("Available devices").font(.headline)
                if model.discovered.isEmpty {
                    Text("No phone connected. Pair a device from Settings or complete onboarding.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.discovered) { peer in
                    Button("\(peer.name)  \(peer.verificationKey)") { model.pair(peer) }
                }
            }
            Spacer()
            if let error = model.sessionError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ringerBinding: Binding<Int> {
        Binding(
            get: { model.live.ringerMode ?? 2 },
            set: { model.setRingerMode($0) }
        )
    }

    private func deviceCard(_ device: ConnectedPeer) -> some View {
        VStack(alignment: .leading) {
            Text(device.name).font(.title3.weight(.semibold))
            HStack {
                Text(device.isConnected ? "Connected" : "Disconnected")
                    .foregroundStyle(device.isConnected ? .green : .secondary)
                if !device.isConnected {
                    Button("Connect") { model.reconnect(device) }
                        .controlSize(.small)
                }
            }
            if model.paired.count > 1 {
                Picker("Device", selection: $model.selectedDeviceID) {
                    ForEach(model.paired) { peer in
                        Text(peer.name).tag(Optional(peer.id))
                    }
                }
                .onChange(of: model.selectedDeviceID) { _, _ in model.refreshDevice() }
            }
        }
    }

    private func mediaCard(_ session: PlaybackInfo, connected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let app = session.appName, !app.isEmpty {
                Text(app).font(.caption).foregroundStyle(.secondary)
            }
            Text(session.trackTitle ?? "Playback").font(.headline)
            Text(session.artist ?? session.source).foregroundStyle(.secondary)
            HStack {
                if session.canGoPrevious != false {
                    Button {
                        model.sendMediaAction(.previous, source: session.source)
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .disabled(!connected)
                }
                Button {
                    model.sendMediaAction(session.isPlaying ? .pause : .play, source: session.source)
                } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(!connected)
                if session.canGoNext != false {
                    Button {
                        model.sendMediaAction(.next, source: session.source)
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(!connected)
                }
            }
            .buttonStyle(.borderless)
            StreamVolumeRow(
                title: "Media volume",
                type: nil,
                level: session.volume,
                enabled: connected
            ) { model.sendMediaAction(.volumeUpdate, source: session.source, value: Double($0)) }
            if session.canSeek == true, let max = session.maxSeekTime, max > 0 {
                Slider(
                    value: Binding(
                        get: { session.position ?? 0 },
                        set: { model.sendMediaAction(.seek, source: session.source, value: $0) }
                    ),
                    in: (session.minSeekTime ?? 0)...max
                )
                .disabled(!connected)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StreamVolumeRow: View {
    var title: String?
    var type: AudioStreamType?
    var level: Int
    var enabled: Bool
    var onCommit: (Int) -> Void
    @State private var value: Double

    init(title: String? = nil, type: AudioStreamType?, level: Int, enabled: Bool, onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.type = type
        self.level = level
        self.enabled = enabled
        self.onCommit = onCommit
        _value = State(initialValue: Double(level))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title ?? type?.railLabel ?? "Volume")
                Spacer()
                Text("\(Int(value))")
            }
            .font(.caption)
            Slider(value: $value, in: 0...100, step: 1) { editing in
                if !editing { onCommit(Int(value.rounded())) }
            }
            .disabled(!enabled)
        }
        .onChange(of: level) { _, newValue in
            value = Double(newValue)
        }
    }
}

private extension AudioStreamType {
    var railLabel: String {
        switch self {
        case .media: "Media"
        case .ring: "Ring"
        case .notification: "Notification"
        case .alarm: "Alarm"
        case .voiceCall: "Call"
        }
    }
}
