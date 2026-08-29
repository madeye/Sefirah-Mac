import AppKit
import Foundation
import SefirahCore
import SwiftUI

@MainActor
@Observable
final class AppModel: PairingDecider {
    var hasCompletedOnboarding: Bool
    var sessionError: String?
    var qrImage: NSImage?
    var qrDeepLink: String = ""
    var discovered: [DiscoveredPeer] = []
    var paired: [ConnectedPeer] = []
    var selectedDeviceID: String?
    var pendingPairing: DiscoveredPeer?
    var notifications: [NotificationSnapshot] = []
    var conversations: [ConversationSnapshot] = []
    var messages: [MessageSnapshot] = []
    var selectedThreadID: Int64?
    var composeText: String = ""
    var callLogs: [CallLogRecord] = []
    var apps: [ApplicationRecord] = []
    var live = DeviceLiveState()
    var general = GeneralSettings()
    var serverPort: Int?
    var incomingCall: CallInfo?
    var showMainWindow = true
    /// Drives the single tool-failure alert in RootView.
    var toolFailure: ToolFailure?
    /// Keys of running scrcpy sessions (device id, or "<device>:<package>").
    var mirroringKeys: Set<String> = []
    /// Keys whose launch is still in the adb phase (before scrcpy has spawned).
    var pendingMirrorKeys: Set<String> = []
    var bundledScrcpyVersion: String? { bundledTools?.version }
    var adbRestartResult: String?

    private var pairingContinuation: CheckedContinuation<Bool, Never>?
    private(set) var session: SessionManager?
    private let database: AppDatabase
    private let hub: FeatureHub
    private let settings: SettingsStore
    private let identity: DeviceIdentity
    private let localDevice: LocalDeviceRecord
    private let bundledTools = BundledTools.locate()
    private let scrcpyRunner: any ScrcpyRunning = ScrcpyProcessRunner()
    private let commandRunner: any CommandRunning = ProcessCommandRunner()
    private var terminateObserver: NSObjectProtocol?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sefirah", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Sefirah")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let loadedSettings = SettingsStore(directory: support.appendingPathComponent("settings"))
        let loadedGeneral = (try? loadedSettings.loadGeneral()) ?? GeneralSettings()

        var startupError: String?
        let db: AppDatabase
        do {
            db = try AppDatabase(fileURL: support.appendingPathComponent(SefirahConstants.databaseFileName))
        } catch {
            db = try! AppDatabase(inMemory: ())
            startupError = "Database: \(error.localizedDescription)"
        }

        let featureHub = FeatureHub(database: db)
        featureHub.actionsCatalog = loadedGeneral.actions

        let store = IdentityStore(directory: support.appendingPathComponent("identity"))
        let loadedIdentity = (try? store.loadOrCreate()) ?? (try! IdentityStore.generate())
        let repo = DeviceRepository(database: db)
        let name = loadedGeneral.localDeviceName.isEmpty
            ? (Host.current().localizedName ?? "Mac")
            : loadedGeneral.localDeviceName
        let loadedLocal = (try? repo.ensureLocalDevice(name: name))
            ?? LocalDeviceRecord(deviceId: UUID().uuidString, deviceName: name)

        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
        sessionError = startupError
        qrImage = nil
        selectedDeviceID = nil
        pendingPairing = nil
        selectedThreadID = nil
        pairingContinuation = nil
        session = nil
        database = db
        hub = featureHub
        settings = loadedSettings
        identity = loadedIdentity
        localDevice = loadedLocal
        general = loadedGeneral

        do {
            let configuration = SessionConfiguration(
                identity: loadedIdentity,
                localDevice: loadedLocal,
                model: Host.current().localizedName ?? "Mac",
                repository: repo
            )
            let manager = try SessionManager(configuration: configuration)
            manager.pairingDecider = self
            manager.eventHandler = { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
            session = manager
            serverPort = try manager.startListening()
            try? manager.startDiscovery()
            let payload = try manager.pairingPayload()
            qrDeepLink = try payload.deepLink()
            qrImage = QrCodeImage.make(qrDeepLink)
            if qrImage == nil, sessionError == nil {
                sessionError = "Could not render pairing QR code"
            }
        } catch {
            sessionError = error.localizedDescription
        }

        paired = (try? DeviceRepository(database: db).fetchPairedDevices().map {
            ConnectedPeer(
                id: $0.deviceId,
                name: $0.name,
                model: $0.model,
                address: $0.addresses.first?.address ?? "",
                port: 5150,
                certificateDER: $0.certificate,
                isConnected: false
            )
        }) ?? []
        selectedDeviceID = paired.first?.id
        refreshDevice()

        let runner = scrcpyRunner
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in runner.terminateAll() }
    }

    var selectedDevice: ConnectedPeer? {
        paired.first { $0.id == selectedDeviceID }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
        showMainWindow = true
    }

    func pair(_ peer: DiscoveredPeer) {
        session?.pair(deviceId: peer.id)
    }

    func reconnect(_ peer: ConnectedPeer) {
        if let host = PeerAddress.reconnectable(peer.address) {
            session?.connect(deviceId: peer.id, host: host, port: peer.port)
        }
        session?.reconnectPairedDevices()
    }

    private func upsertPaired(_ peer: ConnectedPeer) {
        if let index = paired.firstIndex(where: { $0.id == peer.id }) {
            paired[index] = peer
            return
        }
        paired.removeAll { $0.id == peer.id }
        paired.append(peer)
    }

    func acceptPendingPair() {
        pairingContinuation?.resume(returning: true)
        pairingContinuation = nil
        pendingPairing = nil
    }

    func declinePendingPair() {
        pairingContinuation?.resume(returning: false)
        pairingContinuation = nil
        pendingPairing = nil
    }

    func acceptPairing(_ peer: DiscoveredPeer) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pendingPairing = peer
                self.pairingContinuation = continuation
            }
        }
    }

    func replyToNotification(_ note: NotificationSnapshot, text: String) {
        guard let key = note.replyResultKey else { return }
        session?.send(to: note.deviceId, hub.reply(deviceId: note.deviceId, notificationKey: note.notificationKey, replyResultKey: key, text: text))
    }

    func invokeNotification(_ note: NotificationSnapshot, action: NotificationAction) {
        session?.send(
            to: note.deviceId,
            hub.invokeAction(deviceId: note.deviceId, notificationKey: note.notificationKey, index: action.actionIndex, label: action.label ?? "")
        )
    }

    func sendSms() {
        guard let deviceID = selectedDeviceID, let thread = selectedThreadID, !composeText.isEmpty else { return }
        let conversation = conversations.first { $0.threadId == thread }
        let message = hub.sendSms(threadId: thread, addresses: conversation?.addresses ?? [], body: composeText)
        session?.send(to: deviceID, message)
        composeText = ""
    }

    func findPhone() {
        toggleFindPhone(start: true)
    }

    func toggleFindPhone(start: Bool? = nil) {
        guard let deviceID = selectedDeviceID else { return }
        let playing = start ?? !live.soundPlaying
        session?.send(to: deviceID, hub.playSound(isPlaying: playing))
        live.soundPlaying = playing
    }

    func toggleDnd() {
        guard let deviceID = selectedDeviceID else { return }
        let enabled = !(live.dndEnabled ?? false)
        session?.send(to: deviceID, .dndState(DndState(isEnabled: enabled)))
        live.dndEnabled = enabled
    }

    func setRingerMode(_ mode: Int) {
        guard let deviceID = selectedDeviceID else { return }
        session?.send(to: deviceID, hub.setRingerMode(mode))
        live.ringerMode = mode
    }

    func setAudioLevel(_ streamType: AudioStreamType, level: Int) {
        guard let deviceID = selectedDeviceID else { return }
        session?.send(to: deviceID, hub.setAudioLevel(streamType, level: level))
        live.audioStreams[streamType] = level
    }

    func sendMediaAction(_ type: MediaActionType, source: String, value: Double? = nil) {
        guard let deviceID = selectedDeviceID else { return }
        session?.send(to: deviceID, hub.mediaAction(type, source: source, value: value))
        if let index = live.playback.firstIndex(where: { $0.source == source }) {
            switch type {
            case .play: live.playback[index].isPlaying = true
            case .pause, .stop: live.playback[index].isPlaying = false
            case .volumeUpdate:
                if let value { live.playback[index].volume = Int(value) }
            case .seek:
                if let value { live.playback[index].position = value }
            default: break
            }
        }
    }

    func sendClipboard() {
        guard let deviceID = selectedDeviceID else { return }
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:])
        {
            session?.send(to: deviceID, hub.clipboard(type: "image/png", content: png.base64EncodedString()))
            return
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        session?.send(to: deviceID, hub.clipboard(type: "text/plain", content: text))
    }

    func launchScrcpy(package: String? = nil, appName: String? = nil) {
        Task { await launchScrcpyAsync(package: package, appName: appName) }
    }

    func launchScrcpyAsync(package: String? = nil, appName: String? = nil) async {
        guard let device = selectedDevice else { return }
        let key = package.map { "\(device.id):\($0)" } ?? device.id
        // Ignore re-entrant launches while the adb phase is still running for this key.
        guard !pendingMirrorKeys.contains(key) else { return }
        pendingMirrorKeys.insert(key)
        defer { pendingMirrorKeys.remove(key) }
        let deviceSettings = (try? settings.loadDevice(id: device.id)) ?? DeviceSettings(deviceId: device.id)
        let env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let general = self.general
        let bundledTools = self.bundledTools
        func makePlan(_ serial: String?) throws -> ScrcpyLaunchPlan {
            try ScrcpyLaunchPlanner.plan(
                general: general, device: deviceSettings, bundled: bundledTools,
                serial: serial, package: package, appName: appName,
                baseEnvironment: env, home: home,
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0.path) }
            )
        }

        // Resolve tools first with serial nil so tool errors surface before any adb call.
        let base: ScrcpyLaunchPlan
        do {
            base = try makePlan(nil)
        } catch {
            toolFailure = ToolFailure(
                title: "Screen mirroring unavailable",
                message: error.localizedDescription,
                detail: "Bundled scrcpy: \(bundledScrcpyVersion ?? "missing")"
            )
            return
        }

        // Optional Wi-Fi connect + serial selection.
        var serial: String?
        if let adb = base.adb {
            let client = AdbClient(adb: adb, environment: base.environment, runner: commandRunner)
            if deviceSettings.adbTcpipModeEnabled {
                do {
                    serial = try await client.tryConnectTcp(host: device.address, model: device.model)
                } catch {
                    toolFailure = ToolFailure(
                        title: "Could not reach \(device.name) over ADB",
                        message: error.localizedDescription,
                        detail: "Enable Wireless debugging, or connect once over USB so Sefirah can switch the phone to TCP/IP mode."
                    )
                    return
                }
            } else if let devices = try? await client.devices() {
                serial = ScrcpyDeviceSelection.serial(
                    devices: devices, peerModel: device.model, preference: deviceSettings.scrcpyDevicePreference
                )
            } // adb listing failures are non-fatal here; scrcpy reports its own error which we surface on exit.
        }

        let plan: ScrcpyLaunchPlan
        if let serial, let withSerial = try? makePlan(serial) { plan = withSerial } else { plan = base }
        do {
            try scrcpyRunner.launch(plan, key: key) { [weak self] exit in
                Task { @MainActor in self?.handleScrcpyExit(exit, key: key, plan: plan) }
            }
            mirroringKeys.insert(key)
        } catch {
            toolFailure = ToolFailure(title: "Could not start scrcpy", message: error.localizedDescription, detail: plan.executable.path)
        }
    }

    private func handleScrcpyExit(_ exit: ScrcpyExit, key: String, plan: ScrcpyLaunchPlan) {
        // A relaunch with the same key terminates the previous process; the runner already
        // tracks the replacement, so this exit belongs to the old one and must not clear the key.
        guard !scrcpyRunner.runningKeys.contains(key) else { return }
        mirroringKeys.remove(key)
        switch exit {
        case .normal:
            return
        case .failure(let code, let stderr), .signaled(let code, let stderr):
            toolFailure = ToolFailure(
                title: "scrcpy exited (code \(code))",
                message: ScrcpyDiagnostics.hint(exit: exit) ?? "scrcpy reported an error.",
                detail: stderr.isEmpty ? plan.executable.path : stderr
            )
        }
    }

    func stopMirroring(key: String? = nil) {
        if let key {
            scrcpyRunner.terminate(key: key)
        } else {
            scrcpyRunner.terminateAll()
        }
    }

    func isMirroring(_ deviceId: String) -> Bool {
        mirroringKeys.contains(deviceId)
    }

    func isMirrorPending(_ key: String) -> Bool {
        pendingMirrorKeys.contains(key)
    }

    /// True when Mirror can work: bundled tools present or a custom scrcpy path set.
    var canMirror: Bool {
        if bundledTools != nil { return true }
        if !general.scrcpyPath.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        guard let id = selectedDeviceID else { return false }
        return !deviceSettings(for: id).scrcpyPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The adb the app would use for troubleshooting commands (override or bundled).
    private var resolvedAdb: URL? {
        let override = general.adbPath.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { return URL(fileURLWithPath: override) }
        return bundledTools?.adb
    }

    func restartAdbServer() {
        guard let adb = resolvedAdb else {
            adbRestartResult = "No adb available."
            return
        }
        adbRestartResult = "Restarting…"
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        if env["PATH"] == nil { env["PATH"] = ScrcpyLaunchPlanner.defaultPath }
        let runner = commandRunner
        Task {
            do {
                _ = try await runner.run(adb, ["kill-server"], environment: env, timeout: 5)
                let start = try await runner.run(adb, ["start-server"], environment: env, timeout: 10)
                adbRestartResult = start.exitCode == 0
                    ? "ADB server restarted."
                    : "adb start-server failed (exit \(start.exitCode)): \(start.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                adbRestartResult = error.localizedDescription
            }
        }
    }

    func openThirdPartyNotices() {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("scrcpy/NOTICES.md"),
           FileManager.default.fileExists(atPath: url.path)
        {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/Genymobile/scrcpy/blob/master/LICENSE")!)
        }
    }

    func deviceSettings(for deviceId: String) -> DeviceSettings {
        (try? settings.loadDevice(id: deviceId)) ?? DeviceSettings(deviceId: deviceId)
    }

    func updateDeviceSettings(for deviceId: String, _ mutate: (inout DeviceSettings) -> Void) {
        var current = deviceSettings(for: deviceId)
        mutate(&current)
        do {
            try settings.saveDevice(current)
        } catch {
            toolFailure = ToolFailure(title: "Could not save device settings", message: error.localizedDescription, detail: nil)
        }
    }

    func runAction(_ item: ActionItem) {
        execute(ActionRunner.plan(item))
    }

    func execute(_ plan: ActionExecution) {
        guard !plan.command.isEmpty else { return }
        if plan.kind == "link", let url = URL(string: plan.arguments.first ?? "") {
            NSWorkspace.shared.open(url)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.command)
        process.arguments = plan.arguments
        do {
            try process.run()
        } catch {
            toolFailure = ToolFailure(title: "Could not run action", message: error.localizedDescription, detail: plan.command)
        }
    }

    func openSftp() {
        guard let sftp = live.lastSftp, let device = selectedDevice else { return }
        let path = sftp.paths.first
        if let url = SftpBrowse.finderURL(
            host: device.address,
            port: sftp.port,
            username: sftp.username,
            password: sftp.password,
            path: path
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    func saveGeneral() {
        try? settings.saveGeneral(general)
        hub.actionsCatalog = general.actions
        if let id = selectedDeviceID {
            sendActionList(to: id)
        }
    }

    func sendActionList(to deviceId: String) {
        session?.send(to: deviceId, .actionList(ActionRunner.actionList(from: general.actions)))
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "sefirah" else { return }
        if url.host == "pair", let payload = try? QrCodePayload.parseDeepLink(url.absoluteString),
           let address = payload.addresses.first
        {
            session?.connect(deviceId: payload.deviceId, host: address, port: payload.port)
        } else if let package = url.host, !package.isEmpty {
            launchScrcpy(package: package)
        }
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .discovered(let peer):
            if !discovered.contains(where: { $0.id == peer.id }) {
                discovered.append(peer)
            }
        case .pairingRequested(let peer):
            pendingPairing = peer
        case .paired(let peer), .connected(let peer):
            upsertPaired(peer)
            selectedDeviceID = peer.id
            completeOnboarding()
            refreshDevice()
            sendActionList(to: peer.id)
            session?.send(to: peer.id, .requestApplicationList)
        case .disconnected(let deviceId, let forced):
            if let index = paired.firstIndex(where: { $0.id == deviceId }) {
                paired[index].isConnected = false
            }
            if !forced {
                session?.reconnectPairedDevices()
            }
        case .inboundMessage(let deviceId, let message):
            let result = try? hub.handle(deviceId: deviceId, message)
            apply(result?.effects ?? [], deviceId: deviceId)
            if deviceId == selectedDeviceID {
                refreshDevice()
            }
        }
    }

    func refreshDevice() {
        guard let id = selectedDeviceID else { return }
        notifications = (try? hub.notifications(deviceId: id)) ?? []
        conversations = (try? hub.conversations(deviceId: id)) ?? []
        callLogs = (try? hub.callLogs(deviceId: id)) ?? []
        apps = (try? hub.apps(deviceId: id)) ?? []
        live = hub.liveState(deviceId: id)
        incomingCall = live.incomingCall
        if let thread = selectedThreadID {
            messages = (try? hub.messages(deviceId: id, threadId: thread)) ?? []
        }
    }

    func selectThread(_ threadId: Int64) {
        selectedThreadID = threadId
        refreshDevice()
        if let deviceID = selectedDeviceID {
            session?.send(to: deviceID, .threadRequest(ThreadRequest(threadId: threadId)))
        }
    }

    private func apply(_ effects: [FeatureEffect], deviceId: String) {
        for effect in effects {
            switch effect {
            case .applyClipboard(let info):
                ClipboardApply.apply(info)
            case .receiveFiles(let info):
                startFileReceive(deviceId: deviceId, info: info)
            case .executeAction(let execution):
                execute(execution)
            }
        }
    }

    private func startFileReceive(deviceId: String, info: FileTransferInfo) {
        guard let peer = paired.first(where: { $0.id == deviceId }) else { return }
        let destination: URL
        if info.isClipboard {
            destination = FileManager.default.temporaryDirectory.appendingPathComponent("SefirahClipboard", isDirectory: true)
        } else {
            destination = URL(fileURLWithPath: general.receivedFilesPath, isDirectory: true)
        }
        let localIdentity = self.identity
        let cert = peer.certificateDER
        let host = peer.address
        let port = info.serverInfo.port
        Task.detached { [weak self] in
            do {
                let urls = try await FileTransferClient.receive(
                    files: info.files,
                    destination: destination,
                    host: host,
                    port: port,
                    identity: localIdentity,
                    pinnedCertificateDER: cert
                )
                if info.isClipboard, let url = urls.first {
                    await MainActor.run {
                        ClipboardApply.applyFile(url, mimeType: info.files.first?.mimeType)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.sessionError = error.localizedDescription
                }
            }
        }
    }

}

struct ToolFailure: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var detail: String?
}
