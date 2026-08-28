import Foundation
import Network
import os
import Security

private let sessionLog = Logger(subsystem: "io.github.madeye.sefirah.mac", category: "session")

public protocol PairingDecider: AnyObject, Sendable {
    func acceptPairing(_ peer: DiscoveredPeer) async -> Bool
}

public struct SessionConfiguration: Sendable {
    public var identity: DeviceIdentity
    public var localDevice: LocalDeviceRecord
    public var model: String
    public var repository: DeviceRepository
    public var portRange: ClosedRange<Int>
    public var localOnly: Bool

    public init(
        identity: DeviceIdentity,
        localDevice: LocalDeviceRecord,
        model: String = "Mac",
        repository: DeviceRepository,
        portRange: ClosedRange<Int> = SefirahConstants.Ports.controlRange,
        localOnly: Bool = false
    ) {
        self.identity = identity
        self.localDevice = localDevice
        self.model = model
        self.repository = repository
        self.portRange = portRange
        self.localOnly = localOnly
    }
}

public final class SessionManager: @unchecked Sendable {
    public private(set) var serverPort: Int?
    public var eventHandler: (@Sendable (SessionEvent) -> Void)?
    public weak var pairingDecider: PairingDecider?

    private let configuration: SessionConfiguration
    private let queue: DispatchQueue
    private let stash = CertificateStash()
    private let secIdentity: SecIdentity

    private var listener: NWListener?
    private var connections: [UUID: LiveLink] = [:]
    private var discovered: [String: DiscoveredPeer] = [:]
    private var connectingIDs = Set<String>()
    private var udp: UDPDiscovery?
    private var bonjour: BonjourDiscovery?
    private var broadcastTimer: DispatchSourceTimer?

    public init(configuration: SessionConfiguration, queue: DispatchQueue = DispatchQueue(label: "io.github.madeye.sefirah.session")) throws {
        self.configuration = configuration
        self.queue = queue
        self.secIdentity = try SecIdentityFactory.makeIdentity(configuration.identity)
    }

    public var localDeviceId: String { configuration.localDevice.deviceId }

    public func startListening() throws -> Int {
        var lastError: Error?
        for port in configuration.portRange {
            do {
                let parameters = TLSFactory.parameters(
                    identity: secIdentity,
                    policy: .stash,
                    stash: stash,
                    queue: queue
                )
                if configuration.localOnly {
                    parameters.acceptLocalOnly = true
                    parameters.requiredInterfaceType = .loopback
                }
                guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { continue }
                let listener = try NWListener(using: parameters, on: nwPort)
                let started = try start(listener: listener, port: port)
                return started
            } catch {
                lastError = error
            }
        }
        throw lastError ?? POSIXError(.EADDRINUSE)
    }

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            broadcastTimer?.cancel()
            broadcastTimer = nil
            udp?.stop()
            udp = nil
            bonjour?.stop()
            bonjour = nil
            for link in connections.values {
                link.connection.cancel()
            }
            connections.removeAll()
        }
    }

    public func startDiscovery() throws {
        let port = try requireServerPort()
        let udp = UDPDiscovery(localDeviceId: localDeviceId, queue: queue)
        udp.onBroadcast = { [weak self] broadcast, host in
            self?.rememberAddress(deviceId: broadcast.deviceId, host: host)
            self?.connect(deviceId: broadcast.deviceId, host: host, port: broadcast.port)
        }
        try udp.start()
        self.udp = udp
        startBroadcastTimer(port: port)

        let bonjour = BonjourDiscovery(localDeviceId: localDeviceId, queue: queue)
        bonjour.onResolved = { [weak self] deviceId, _, host, resolvedPort in
            self?.rememberAddress(deviceId: deviceId, host: host)
            self?.connect(deviceId: deviceId, host: host, port: resolvedPort)
        }
        try bonjour.advertise(
            deviceId: localDeviceId,
            deviceName: configuration.localDevice.deviceName,
            serverPort: port
        )
        bonjour.startBrowsing()
        self.bonjour = bonjour
        reconnectPairedDevices()
    }

    /// Retry TLS to last-known IPv4/global addresses of paired phones.
    public func reconnectPairedDevices() {
        queue.async { [weak self] in
            guard let self else { return }
            let devices = (try? self.configuration.repository.fetchPairedDevices()) ?? []
            for device in devices {
                for entry in device.addresses where entry.isEnabled {
                    guard let host = PeerAddress.reconnectable(entry.address) else { continue }
                    self.connectLocked(deviceId: device.deviceId, host: host, port: SefirahConstants.Ports.controlRange.lowerBound)
                }
            }
        }
    }

    public func pairingPayload() throws -> QrCodePayload {
        let port = try requireServerPort()
        var addresses = LocalIPv4Addresses.all()
        if configuration.localOnly {
            addresses = ["127.0.0.1"]
        }
        return QrCodePayload(
            addresses: addresses,
            port: port,
            deviceId: localDeviceId,
            deviceName: configuration.localDevice.deviceName
        )
    }

    public func connect(deviceId: String, host: String, port: Int) {
        queue.async { [weak self] in
            self?.connectLocked(deviceId: deviceId, host: canonicalHost(host), port: port)
        }
    }

    public func pair(deviceId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard var peer = self.discovered[deviceId],
                  let link = self.liveLink(for: deviceId)
            else { return }
            peer.isPairing = true
            self.discovered[deviceId] = peer
            link.connection.send(.pairMessage(PairMessage(pair: true)))
        }
    }

    public func send(to deviceId: String, _ message: SocketMessage) {
        queue.async { [weak self] in
            self?.liveLink(for: deviceId)?.connection.send(message)
        }
    }

    public func disconnect(deviceId: String, forced: Bool = true) {
        queue.async { [weak self] in
            guard let self else { return }
            if let link = self.liveLink(for: deviceId) {
                self.tearDown(link, forced: forced)
            }
        }
    }

    public func broadcast(_ message: SocketMessage) {
        queue.async { [weak self] in
            guard let self else { return }
            for link in self.connections.values where link.pairedDeviceId != nil {
                link.connection.send(message)
            }
        }
    }

    // MARK: - Listen / connect

    private func start(listener: NWListener, port: Int) throws -> Int {
        let group = DispatchGroup()
        group.enter()
        let startState = ListenerStartState()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                startState.leave(group)
            case .failed(let error):
                startState.fail(error, group: group)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            sessionLog.info("inbound TCP from \(String(describing: connection.endpoint), privacy: .public)")
            self?.queue.async {
                self?.attach(connection, outbound: false, expectedPeer: nil, deviceIdHint: nil)
            }
        }
        listener.start(queue: queue)
        let wait = group.wait(timeout: .now() + 2)
        if wait == .timedOut {
            listener.cancel()
            throw POSIXError(.ETIMEDOUT)
        }
        if let startError = startState.error {
            listener.cancel()
            throw startError
        }
        self.listener = listener
        self.serverPort = port
        return port
    }

    private func connectLocked(deviceId: String, host: String, port: Int) {
        if let paired = try? configuration.repository.fetchPairedDevice(id: deviceId) {
            if connections.values.contains(where: { $0.pairedDeviceId == deviceId }) { return }
            if connectingIDs.contains(deviceId) { return }
            connectingIDs.insert(deviceId)
            attachOutbound(
                deviceId: deviceId,
                host: host,
                port: port,
                policy: .pin(paired.certificate)
            )
            return
        }
        if discovered[deviceId] != nil { return }
        if connectingIDs.contains(deviceId) { return }
        connectingIDs.insert(deviceId)
        attachOutbound(deviceId: deviceId, host: host, port: port, policy: .stash)
    }

    private func attachOutbound(deviceId: String, host: String, port: Int, policy: TLSTrustPolicy) {
        let parameters = TLSFactory.parameters(
            identity: secIdentity,
            policy: policy,
            stash: stash,
            queue: queue
        )
        if configuration.localOnly {
            parameters.acceptLocalOnly = true
            parameters.requiredInterfaceType = .loopback
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            connectingIDs.remove(deviceId)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        attach(connection, outbound: true, expectedPeer: {
            if case .pin(let der) = policy { return der }
            return nil
        }(), deviceIdHint: deviceId)
    }

    private func attach(
        _ nw: NWConnection,
        outbound: Bool,
        expectedPeer: Data?,
        deviceIdHint: String?
    ) {
        let link = LiveLink(
            connection: NDJSONConnection(connection: nw, queue: queue),
            outbound: outbound,
            expectedPeerCertificate: expectedPeer,
            deviceIdHint: deviceIdHint
        )
        connections[link.connection.id] = link
        link.connection.onReady = { [weak self, weak link] in
            guard let self, let link else { return }
            self.queue.async {
                guard link.outbound else { return }
                link.connection.send(self.authenticationMessage())
                self.completePinnedReconnect(link)
            }
        }
        link.connection.onMessage = { [weak self, weak link] message in
            guard let self, let link else { return }
            self.queue.async {
                self.handle(message, on: link)
            }
        }
        link.connection.onFailed = { [weak self, weak link] error in
            guard let self, let link else { return }
            self.queue.async {
                sessionLog.error("link failed outbound=\(link.outbound, privacy: .public) \(String(describing: error), privacy: .public)")
                self.tearDown(link, forced: false)
            }
        }
        link.connection.start()
        if outbound, let hint = deviceIdHint {
            queue.asyncAfter(deadline: .now() + 10) { [weak self, weak link] in
                guard let self, let link, self.connections[link.connection.id] != nil,
                      link.pairedDeviceId == nil, link.discoveredId == nil
                else { return }
                sessionLog.error("outbound connect timed out for \(hint, privacy: .public)")
                self.tearDown(link, forced: false)
            }
        }
    }

    /// Paired reconnect (Android `connectPaired`): once the pinned-cert TLS
    /// handshake succeeds and our `Authentication` is sent, the outbound side is
    /// connected. The peer does not reply with its own `Authentication`.
    private func completePinnedReconnect(_ link: LiveLink) {
        guard link.expectedPeerCertificate != nil,
              link.pairedDeviceId == nil,
              let deviceId = link.deviceIdHint,
              connections[link.connection.id] != nil,
              let paired = try? configuration.repository.fetchPairedDevice(id: deviceId)
        else { return }
        connectingIDs.remove(deviceId)
        let address = PeerAddress.reconnectable(link.connection.remoteHost)
            ?? canonicalHost(link.connection.remoteHost)
        let port = link.connection.remotePort == 0 ? SefirahConstants.Ports.controlRange.lowerBound : link.connection.remotePort
        completePaired(paired, link: link, address: address, port: port)
    }

    // MARK: - Messages

    private func handle(_ message: SocketMessage, on link: LiveLink) {
        if case .authentication(let auth) = message {
            link.authenticating = true
            handleAuthentication(auth, on: link)
            flushDeferred(link)
            return
        }
        if link.authenticating {
            link.deferred.append(message)
            return
        }
        route(message, on: link)
    }

    private func handleAuthentication(_ auth: Authentication, on link: LiveLink) {
        // Already completed as a pinned reconnect; a late peer `Authentication` is a no-op.
        if let pairedId = link.pairedDeviceId, pairedId == auth.deviceId {
            link.authenticating = false
            return
        }
        defer {
            link.authenticating = false
            if let hint = link.deviceIdHint {
                connectingIDs.remove(hint)
            }
        }
        let pairedRecord = try? configuration.repository.fetchPairedDevice(id: auth.deviceId)
        guard let certificate = SessionAuthentication.certificate(
            publicKeyBase64: auth.publicKey,
            stashed: stash.take(publicKeyBase64: auth.publicKey),
            pinned: link.expectedPeerCertificate,
            paired: pairedRecord?.certificate
        ), !certificate.isEmpty else {
            sessionLog.error("auth rejected, no cert for \(auth.deviceId, privacy: .public)")
            tearDown(link, forced: true)
            return
        }
        let address = PeerAddress.reconnectable(link.connection.remoteHost)
            ?? canonicalHost(link.connection.remoteHost)
        let port = link.connection.remotePort == 0 ? (serverPort ?? 5150) : link.connection.remotePort

        if let paired = pairedRecord {
            if paired.certificate != certificate {
                tearDown(link, forced: true)
                return
            }
            completePaired(paired, link: link, address: address, port: port)
            return
        }

        let verification = configuration.identity.verificationCode(peerPublicKeyBase64: auth.publicKey)
        var peer = DiscoveredPeer(
            id: auth.deviceId,
            name: auth.deviceName,
            model: auth.model,
            address: address,
            port: port,
            certificateDER: certificate,
            verificationKey: verification
        )
        if let existing = discovered[auth.deviceId],
           let previous = liveLink(for: auth.deviceId),
           previous.connection.id != link.connection.id
        {
            tearDown(previous, forced: true)
            peer.isPairing = existing.isPairing
        }
        discovered[auth.deviceId] = peer
        link.discoveredId = auth.deviceId
        emit(.discovered(peer))
        if !link.outbound {
            link.connection.send(authenticationMessage())
        }
    }

    private func route(_ message: SocketMessage, on link: LiveLink) {
        if case .pairMessage(let pair) = message, let discoveredId = link.discoveredId,
           var peer = discovered[discoveredId]
        {
            handlePair(pair, peer: &peer, link: link)
            discovered[discoveredId] = peer
            return
        }
        if case .disconnect = message {
            tearDown(link, forced: true)
            return
        }
        if let deviceId = link.pairedDeviceId ?? link.discoveredId {
            emit(.inboundMessage(deviceId: deviceId, message))
        }
    }

    private func handlePair(_ pair: PairMessage, peer: inout DiscoveredPeer, link: LiveLink) {
        if peer.isPairing {
            peer.isPairing = false
            if pair.pair {
                finishPairing(peer, link: link)
            }
            return
        }
        if pair.pair {
            emit(.pairingRequested(peer))
            let snapshot = peer
            let connectionID = link.connection.id
            Task { [weak self] in
                let accepted = await self?.pairingDecider?.acceptPairing(snapshot) ?? false
                self?.queue.async {
                    guard let self, let live = self.connections[connectionID] else { return }
                    live.connection.send(.pairMessage(PairMessage(pair: accepted)))
                    if accepted {
                        self.finishPairing(snapshot, link: live)
                    }
                }
            }
        }
    }

    private func finishPairing(_ peer: DiscoveredPeer, link: LiveLink) {
        let host = PeerAddress.reconnectable(peer.address) ?? peer.address
        let record = PairedDeviceRecord(
            deviceId: peer.id,
            name: peer.name,
            model: peer.model,
            certificate: peer.certificateDER,
            lastConnected: Date(),
            addresses: host.isEmpty ? [] : [AddressEntry(address: host, isEnabled: true)]
        )
        try? configuration.repository.upsertPairedDevice(record)
        discovered.removeValue(forKey: peer.id)
        completePaired(record, link: link, address: peer.address, port: peer.port)
        emit(.paired(connectedPeer(from: record, address: peer.address, port: peer.port, connected: true)))
    }

    private func completePaired(
        _ record: PairedDeviceRecord,
        link: LiveLink,
        address: String,
        port: Int
    ) {
        if let other = connections.values.first(where: {
            $0.pairedDeviceId == record.deviceId && $0.connection.id != link.connection.id
        }) {
            tearDown(other, forced: true)
        }
        link.pairedDeviceId = record.deviceId
        link.discoveredId = nil
        var updated = record
        if let usable = PeerAddress.reconnectable(address),
           !updated.addresses.contains(where: { $0.address == usable })
        {
            updated.addresses.append(AddressEntry(address: usable, isEnabled: true))
        }
        updated.lastConnected = Date()
        try? configuration.repository.upsertPairedDevice(updated)
        emit(.connected(connectedPeer(from: updated, address: address, port: port, connected: true)))
    }

    private func flushDeferred(_ link: LiveLink) {
        let pending = link.deferred
        link.deferred.removeAll()
        for message in pending {
            route(message, on: link)
        }
    }

    private func tearDown(_ link: LiveLink, forced: Bool) {
        connections.removeValue(forKey: link.connection.id)
        link.connection.cancel()
        if let hint = link.deviceIdHint {
            connectingIDs.remove(hint)
        }
        if let discoveredId = link.discoveredId {
            discovered.removeValue(forKey: discoveredId)
        }
        if let pairedId = link.pairedDeviceId {
            emit(.disconnected(deviceId: pairedId, forced: forced))
        }
    }

    private func liveLink(for deviceId: String) -> LiveLink? {
        connections.values.first {
            $0.pairedDeviceId == deviceId || $0.discoveredId == deviceId || $0.deviceIdHint == deviceId
        }
    }

    private func authenticationMessage() -> SocketMessage {
        .authentication(
            Authentication(
                deviceId: configuration.localDevice.deviceId,
                deviceName: configuration.localDevice.deviceName,
                publicKey: configuration.identity.publicKeyBase64,
                model: configuration.model
            )
        )
    }

    private func startBroadcastTimer(port: Int) {
        broadcastTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.udp?.broadcast(self.currentBroadcast(port: port))
        }
        timer.resume()
        broadcastTimer = timer
    }

    private func rememberAddress(deviceId: String, host: String) {
        guard let usable = PeerAddress.reconnectable(host) else { return }
        guard var paired = try? configuration.repository.fetchPairedDevice(id: deviceId) else { return }
        if paired.addresses.contains(where: { $0.address == usable }) { return }
        paired.addresses.append(AddressEntry(address: usable, isEnabled: true))
        try? configuration.repository.upsertPairedDevice(paired)
    }

    private func currentBroadcast(port: Int) -> UdpBroadcast {
        UdpBroadcast(port: port, deviceId: localDeviceId, deviceName: configuration.localDevice.deviceName)
    }

    private func requireServerPort() throws -> Int {
        guard let serverPort else { throw POSIXError(.ENOTCONN) }
        return serverPort
    }

    private func connectedPeer(from record: PairedDeviceRecord, address: String, port: Int, connected: Bool) -> ConnectedPeer {
        ConnectedPeer(
            id: record.deviceId,
            name: record.name,
            model: record.model,
            address: address,
            port: port,
            certificateDER: record.certificate,
            isConnected: connected
        )
    }

    private func emit(_ event: SessionEvent) {
        eventHandler?(event)
    }
}

private final class ListenerStartState: @unchecked Sendable {
    private let lock = NSLock()
    private var left = false
    private(set) var error: Error?

    func leave(_ group: DispatchGroup) {
        lock.lock()
        defer { lock.unlock() }
        guard !left else { return }
        left = true
        group.leave()
    }

    func fail(_ error: Error, group: DispatchGroup) {
        lock.lock()
        self.error = error
        lock.unlock()
        leave(group)
    }
}

private final class LiveLink: @unchecked Sendable {
    let connection: NDJSONConnection
    let outbound: Bool
    let expectedPeerCertificate: Data?
    let deviceIdHint: String?
    var authenticating = false
    var deferred: [SocketMessage] = []
    var discoveredId: String?
    var pairedDeviceId: String?

    init(
        connection: NDJSONConnection,
        outbound: Bool,
        expectedPeerCertificate: Data?,
        deviceIdHint: String?
    ) {
        self.connection = connection
        self.outbound = outbound
        self.expectedPeerCertificate = expectedPeerCertificate
        self.deviceIdHint = deviceIdHint
    }
}
