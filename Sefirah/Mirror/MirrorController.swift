import AppKit
import AVFoundation
import Foundation
import OSLog
import SefirahCore

/// Per-session view model: owns the `MirrorSession`, the display layer, the sink and the input handler;
/// hops events to main; implements the reconnect policy and clipboard bridging.
@MainActor
@Observable
final class MirrorController {
    static let logTailLines = 200
    static let reconnectDelay: UInt64 = 1_000_000_000
    private static let log = Logger(subsystem: "io.github.madeye.sefirah.mac", category: "mirror")

    /// Per-device behaviour the controller needs from `DeviceSettings`.
    struct Preferences: Equatable {
        var clipboardReceive = true
        var showClipboardToast = false
        var physicalKeyboard = false
        var forwardHover = false
        var flexDisplay = false
        var maxSize = 0
    }

    let key: String
    let deviceId: String
    let title: String
    /// Package launched on a virtual display (per-app session), nil for the device mirror.
    let package: String?
    let layer = AVSampleBufferDisplayLayer()
    let input = MirrorInputHandler()

    private(set) var state: MirrorState = .idle
    private(set) var deviceModel: String?
    private(set) var codec: StreamCodecID?
    private(set) var audioCodec: StreamCodecID?
    private(set) var videoSize: CGSize?
    private(set) var audioUnavailable = false
    private(set) var isMuted = false
    private(set) var warnings: [String] = []
    private(set) var serverErrors: [String] = []
    private(set) var logLines: [String] = []
    private(set) var config: MirrorSessionConfig?
    private(set) var displayOn = true
    private(set) var capsLockOn = false
    private(set) var numLockOn = false
    /// Last clipboard text received from the phone (banner when `showClipboardToast`).
    private(set) var clipboardBanner: String?
    private(set) var reconnecting = false

    var preferences = Preferences() {
        didSet { applyPreferences() }
    }
    /// Whether the peer is still reachable; consulted before an automatic reconnect.
    var isDeviceOnline: () -> Bool = { true }
    /// Re-resolves the ADB serial and restarts this controller (set by `AppModel`); falls back to `start` with the last config.
    var relaunch: (() async -> Void)?
    /// Called once per session on a terminal failure (the fallback-to-external policy lives in `AppModel`).
    var onFailed: ((MirrorError) -> Void)?

    private let sink: DisplayLayerSink
    private var audioPlayer: AudioPlayer?
    private var session: MirrorSession?
    private var task: Task<Void, Never>?
    private var launcher: ServerLauncher?
    private var userStopped = false
    private var reachedStreaming = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    nonisolated(unsafe) private var activeObserver: NSObjectProtocol?

    init(key: String, deviceId: String, title: String, package: String? = nil) {
        self.key = key
        self.deviceId = deviceId
        self.title = title
        self.package = package
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        sink = DisplayLayerSink(renderer: layer.sampleBufferRenderer)
        input.send = { [weak self] message in self?.send(message) }
        input.currentVideoSize = { [weak self] in
            MainActor.assumeIsolated { self?.session?.currentVideoSize }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterInactive() }
        }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    var isActive: Bool { state.isActive }

    var logTail: String { logLines.joined(separator: "\n") }

    var aspectRatio: CGFloat? {
        guard let videoSize, videoSize.height > 0 else { return nil }
        return videoSize.width / videoSize.height
    }

    /// Shows a failure that happened before a session existed (tool/adb/options errors).
    func fail(_ error: MirrorError) {
        state = .failed(error)
    }

    func addWarning(_ text: String) {
        warnings.append(text)
    }

    func dismissWarnings() {
        warnings = []
        clipboardBanner = nil
    }

    func start(config: MirrorSessionConfig, launcher: ServerLauncher) {
        guard task == nil else { return }
        self.config = config
        self.launcher = launcher
        deviceModel = nil
        codec = nil
        audioCodec = nil
        videoSize = nil
        audioUnavailable = false
        serverErrors = []
        logLines = []
        userStopped = false
        reachedStreaming = false
        reconnecting = false
        displayOn = !config.actions.contains(.displayPower(on: false))
        input.reset()
        applyPreferences()
        var audioSink: AudioPlayer?
        if config.options.audio {
            let player = AudioPlayer(targetLatencyMs: config.audioTargetLatencyMs)
            player.isMuted = isMuted
            player.onError = { [weak self] message in
                Task { @MainActor in self?.addWarning(message) }
            }
            audioSink = player
        }
        audioPlayer = audioSink
        let session = MirrorSession(config: config, launcher: launcher, videoSink: sink, audioSink: audioSink) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.session = session
        state = .preparing(.push)
        task = Task { [weak self] in
            await session.start()
            await MainActor.run { self?.task = nil; self?.session = nil }
        }
    }

    func stop() {
        userStopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnecting = false
        guard let session else {
            if case .failed = state { state = .idle }
            return
        }
        state = .stopping
        Task { await session.stop() }
    }

    /// Synchronous, for app quit.
    nonisolated func emergencyStop() {
        MainActor.assumeIsolated { session?.emergencyStop() }
    }

    func send(_ message: ControlMessage) {
        if case .injectTouch = message {} else {
            Self.log.debug("[\(self.key, privacy: .public)] send \(String(describing: message), privacy: .public)")
        }
        session?.control.send(message)
    }

    /// Down + up of an Android keycode (toolbar buttons).
    func pressKey(_ keycode: Int32) {
        send(.injectKeycode(action: .down, keycode: keycode, repeat: 0, metaState: []))
        send(.injectKeycode(action: .up, keycode: keycode, repeat: 0, metaState: []))
    }

    func toggleMute() {
        isMuted.toggle()
        audioPlayer?.isMuted = isMuted
    }

    /// Live audio pipeline counters (footer / diagnostics).
    var audioStatistics: AudioPlayer.Stats? { audioPlayer?.statistics }

    func toggleDisplayPower() {
        displayOn.toggle()
        send(.setDisplayPower(on: displayOn))
    }

    /// Pushes the Mac clipboard to the phone (used by the toolbar/menu; ⌘V in the surface does the same).
    func pasteFromMac() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        send(.setClipboard(sequence: 0, paste: true, text: text))
    }

    // MARK: - Events

    private func handle(_ event: MirrorEvent) {
        switch event {
        case .state(let new):
            // A stop request keeps "stopping" until the session really ends.
            if state == .stopping, new != .idle, !isFinal(new) { return }
            Self.log.info("[\(self.key, privacy: .public)] state → \(String(describing: new), privacy: .public)")
            if new == .streaming { reachedStreaming = true; reconnectAttempts = 0 }
            state = new
            if case .failed(let error) = new {
                considerReconnect(after: error)
                if !reconnecting { onFailed?(error) }
            }
            if !new.isActive { input.reset() }
        case .deviceName(let name):
            deviceModel = name
        case .videoCodec(let c):
            codec = c
        case .audioCodec(let c):
            audioCodec = c
        case .videoSize(let w, let h, _):
            videoSize = CGSize(width: w, height: h)
        case .audioUnavailable:
            audioUnavailable = true
        case .clipboard(let text):
            guard preferences.clipboardReceive else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if preferences.showClipboardToast { clipboardBanner = text }
        case .clipboardAck:
            break
        case .uhidOutput(let id, let data):
            guard id == HidKeyboard.deviceId, let byte = data.first else { return }
            let leds = HidKeyboard.Leds(rawValue: byte)
            capsLockOn = leds.contains(.capsLock)
            numLockOn = leds.contains(.numLock)
        case .serverLog(let line):
            Self.log.info("[\(self.key, privacy: .public)] \(line, privacy: .public)")
            logLines.append(line)
            if logLines.count > Self.logTailLines { logLines.removeFirst(logLines.count - Self.logTailLines) }
            if line.contains("ERROR:") { serverErrors.append(line) }
        case .warning(let text):
            warnings.append(text)
        }
    }

    private func isFinal(_ s: MirrorState) -> Bool {
        if case .failed = s { return true }
        return s == .idle
    }

    private func applyPreferences() {
        input.keyboardMode = preferences.physicalKeyboard ? .uhid : .sdk
        input.forwardHover = preferences.forwardHover
        input.flexDisplay = preferences.flexDisplay
        input.maxSize = preferences.maxSize
    }

    /// The renderer may need a keyframe after the app was hidden for a while.
    private func resumeAfterInactive() {
        guard state == .streaming else { return }
        send(.resetVideo)
    }

    /// Errors that can follow a working session (socket EOF, server killed by the OS/adb loss).
    private static func isTransient(_ error: MirrorError) -> Bool {
        switch error {
        case .connectionLost, .serverExited, .handshakeTimeout: return true
        default: return false
        }
    }

    /// One automatic retry after a lost connection while streaming, if the device is still online.
    /// The retry goes through `relaunch` (re-resolves the serial, e.g. `adb connect` after a Wi-Fi drop).
    private func considerReconnect(after error: MirrorError) {
        guard Self.isTransient(error), reachedStreaming, !userStopped, reconnectAttempts == 0,
              let config, let launcher, isDeviceOnline() else { return }
        reconnectAttempts += 1
        reconnecting = true
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.reconnectDelay)
            guard !Task.isCancelled, let self, reconnecting else { return }
            reconnecting = false
            if let relaunch {
                await relaunch()
                if task == nil, !state.isActive, !userStopped {
                    // relaunch declined (e.g. device offline): keep the failure visible.
                    state = .failed(error)
                }
            } else {
                var retry = config
                retry.options.scid = UInt32.random(in: 0...0x7fff_ffff)
                start(config: retry, launcher: launcher)
            }
        }
    }
}
