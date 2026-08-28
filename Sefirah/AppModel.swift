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

    private var pairingContinuation: CheckedContinuation<Bool, Never>?
    private(set) var session: SessionManager?
    private let database: AppDatabase
    private let hub: FeatureHub
    private let settings: SettingsStore
    private let identity: DeviceIdentity
    private let localDevice: LocalDeviceRecord

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
        guard let deviceID = selectedDeviceID else { return }
        let deviceSettings = (try? settings.loadDevice(id: deviceID)) ?? DeviceSettings(deviceId: deviceID)
        let path = general.scrcpyPath.isEmpty ? deviceSettings.scrcpyPath : general.scrcpyPath
        guard !path.isEmpty else { return }
        let args = ScrcpyArguments.build(settings: deviceSettings, serial: nil, package: package, appName: appName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
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
        try? process.run()
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


