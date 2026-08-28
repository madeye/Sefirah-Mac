import SefirahCore
import XCTest

final class SessionHandshakeTests: XCTestCase {
    private func makeHarness(serverAccepts: Bool = true) throws -> DualHarness {
        do {
            return try DualHarness(serverAccepts: serverAccepts)
        } catch {
            throw XCTSkip("SecIdentity/mTLS unavailable in unsigned tests: \(error)")
        }
    }

    func testPairAcceptPersistsCertificates() throws {
        let harness = try makeHarness()
        defer { harness.stop() }

        try harness.listen()
        harness.client.manager.connect(deviceId: harness.server.manager.localDeviceId, host: "127.0.0.1", port: harness.serverPort)

        wait(for: [harness.client.discovered], timeout: 8)
        harness.client.manager.pair(deviceId: harness.server.manager.localDeviceId)
        wait(for: [harness.server.paired, harness.client.paired], timeout: 8)

        let storedOnServer = try XCTUnwrap(
            try harness.server.repository.fetchPairedDevice(id: harness.client.manager.localDeviceId)
        )
        XCTAssertEqual(storedOnServer.certificate, harness.client.identity.certificateDER)
        let storedOnClient = try XCTUnwrap(
            try harness.client.repository.fetchPairedDevice(id: harness.server.manager.localDeviceId)
        )
        XCTAssertEqual(storedOnClient.certificate, harness.server.identity.certificateDER)
    }

    func testPairRejectDoesNotPersist() throws {
        let harness = try makeHarness(serverAccepts: false)
        defer { harness.stop() }

        try harness.listen()
        harness.client.manager.connect(deviceId: harness.server.manager.localDeviceId, host: "127.0.0.1", port: harness.serverPort)
        wait(for: [harness.client.discovered], timeout: 8)
        harness.client.manager.pair(deviceId: harness.server.manager.localDeviceId)
        wait(for: [harness.server.pairingRequested], timeout: 8)
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertNil(try harness.server.repository.fetchPairedDevice(id: harness.client.manager.localDeviceId))
        XCTAssertNil(try harness.client.repository.fetchPairedDevice(id: harness.server.manager.localDeviceId))
    }

    func testReconnectWithPinnedCertificate() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        try harness.listen()
        harness.client.manager.connect(deviceId: harness.server.manager.localDeviceId, host: "127.0.0.1", port: harness.serverPort)
        wait(for: [harness.client.discovered], timeout: 8)
        harness.client.manager.pair(deviceId: harness.server.manager.localDeviceId)
        wait(for: [harness.server.paired, harness.client.paired], timeout: 8)

        harness.client.manager.disconnect(deviceId: harness.server.manager.localDeviceId, forced: true)
        wait(for: [harness.server.disconnected], timeout: 8)

        harness.client.resetConnectionExpectations()
        harness.server.resetConnectionExpectations()
        harness.client.manager.connect(deviceId: harness.server.manager.localDeviceId, host: "127.0.0.1", port: harness.serverPort)
        wait(for: [harness.client.connected, harness.server.connected], timeout: 8)
    }

    func testCertMismatchDisconnects() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        try harness.listen()
        harness.client.manager.connect(deviceId: harness.server.manager.localDeviceId, host: "127.0.0.1", port: harness.serverPort)
        wait(for: [harness.client.discovered], timeout: 8)
        harness.client.manager.pair(deviceId: harness.server.manager.localDeviceId)
        wait(for: [harness.server.paired, harness.client.paired], timeout: 8)
        harness.client.manager.stop()

        let imposterDB = try AppDatabase(inMemory: ())
        let imposterRepo = DeviceRepository(database: imposterDB)
        let local = try imposterRepo.ensureLocalDevice(name: "Imposter")
        // Keep the original client device id so the server treats this as a reconnect.
        let stolen = LocalDeviceRecord(deviceId: harness.client.manager.localDeviceId, deviceName: "Imposter")
        try imposterDB.dbQueue.write { db in
            try local.delete(db)
            try stolen.insert(db)
        }
        let newIdentity = try IdentityStore.generate()
        XCTAssertNotEqual(newIdentity.certificateDER, harness.client.identity.certificateDER)

        let imposter = try PeerNode(
            identity: newIdentity,
            repository: imposterRepo,
            local: stolen,
            accept: true
        )
        defer { imposter.manager.stop() }
        imposter.manager.connect(
            deviceId: harness.server.manager.localDeviceId,
            host: "127.0.0.1",
            port: harness.serverPort
        )
        wait(for: [harness.server.disconnected], timeout: 8)
        let stored = try XCTUnwrap(
            try harness.server.repository.fetchPairedDevice(id: harness.client.manager.localDeviceId)
        )
        XCTAssertEqual(stored.certificate, harness.client.identity.certificateDER)
    }
}

private final class AcceptAll: PairingDecider, @unchecked Sendable {
    let accept: Bool
    init(accept: Bool) { self.accept = accept }
    func acceptPairing(_ peer: DiscoveredPeer) async -> Bool { accept }
}

private final class PeerNode: @unchecked Sendable {
    let identity: DeviceIdentity
    let repository: DeviceRepository
    let manager: SessionManager
    let decider: AcceptAll
    var discovered: XCTestExpectation
    var pairingRequested: XCTestExpectation
    var paired: XCTestExpectation
    var connected: XCTestExpectation
    var disconnected: XCTestExpectation

    init(identity: DeviceIdentity, repository: DeviceRepository, local: LocalDeviceRecord, accept: Bool) throws {
        self.identity = identity
        self.repository = repository
        self.decider = AcceptAll(accept: accept)
        let configuration = SessionConfiguration(
            identity: identity,
            localDevice: local,
            model: local.deviceName,
            repository: repository,
            localOnly: true
        )
        manager = try SessionManager(configuration: configuration)
        manager.pairingDecider = decider
        discovered = XCTestExpectation(description: "discovered-\(local.deviceName)")
        pairingRequested = XCTestExpectation(description: "pairing-\(local.deviceName)")
        paired = XCTestExpectation(description: "paired-\(local.deviceName)")
        connected = XCTestExpectation(description: "connected-\(local.deviceName)")
        disconnected = XCTestExpectation(description: "disconnected-\(local.deviceName)")
        disconnected.assertForOverFulfill = false
        manager.eventHandler = { [weak self] event in
            switch event {
            case .discovered: self?.discovered.fulfill()
            case .pairingRequested: self?.pairingRequested.fulfill()
            case .paired: self?.paired.fulfill()
            case .connected: self?.connected.fulfill()
            case .disconnected: self?.disconnected.fulfill()
            case .inboundMessage: break
            }
        }
    }

    func resetConnectionExpectations() {
        connected = XCTestExpectation(description: "reconnected")
        disconnected = XCTestExpectation(description: "redisconnected")
        disconnected.assertForOverFulfill = false
        manager.eventHandler = { [weak self] event in
            switch event {
            case .connected: self?.connected.fulfill()
            case .disconnected: self?.disconnected.fulfill()
            default: break
            }
        }
    }
}

private final class DualHarness {
    let server: PeerNode
    let client: PeerNode
    var serverPort: Int = 0

    init(serverAccepts: Bool = true) throws {
        let serverDB = try AppDatabase(inMemory: ())
        let clientDB = try AppDatabase(inMemory: ())
        let serverRepo = DeviceRepository(database: serverDB)
        let clientRepo = DeviceRepository(database: clientDB)
        let serverLocal = try serverRepo.ensureLocalDevice(name: "Server")
        let clientLocal = try clientRepo.ensureLocalDevice(name: "Client")
        server = try PeerNode(
            identity: IdentityStore.generate(),
            repository: serverRepo,
            local: serverLocal,
            accept: serverAccepts
        )
        client = try PeerNode(
            identity: IdentityStore.generate(),
            repository: clientRepo,
            local: clientLocal,
            accept: true
        )
    }

    func listen() throws {
        serverPort = try server.manager.startListening()
        _ = try client.manager.startListening()
    }

    func stop() {
        client.manager.stop()
        server.manager.stop()
    }
}
