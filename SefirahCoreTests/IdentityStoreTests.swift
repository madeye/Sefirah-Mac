import SefirahCore
import XCTest

final class IdentityStoreTests: XCTestCase {
    func testGenerateIsP256AndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sefirah-id-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdentityStore(directory: directory)
        let first = try store.loadOrCreate()
        XCTAssertFalse(first.spki.isEmpty)
        XCTAssertFalse(first.certificateDER.isEmpty)
        XCTAssertFalse(first.privateKeyDER.isEmpty)
        XCTAssertFalse(first.publicKeyBase64.isEmpty)

        let second = try store.loadOrCreate()
        XCTAssertEqual(first, second)

        let reloaded = try IdentityStore(directory: directory).load()
        XCTAssertEqual(reloaded.spki, first.spki)
        XCTAssertEqual(reloaded.certificateDER, first.certificateDER)
    }

    func testTwoIdentitiesShareVerificationCode() throws {
        let a = try IdentityStore.generate()
        let b = try IdentityStore.generate()
        XCTAssertNotEqual(a.spki, b.spki)
        XCTAssertEqual(
            a.verificationCode(peerSPKI: b.spki),
            b.verificationCode(peerSPKI: a.spki)
        )
        XCTAssertEqual(
            a.verificationCode(peerPublicKeyBase64: b.publicKeyBase64),
            b.verificationCode(peerPublicKeyBase64: a.publicKeyBase64)
        )
    }

    func testGeneratedIdentityCanListenAndBuildPairingQR() throws {
        let database = try AppDatabase(inMemory: ())
        let repository = DeviceRepository(database: database)
        let local = try repository.ensureLocalDevice(name: "Mac")
        let manager = try SessionManager(
            configuration: SessionConfiguration(
                identity: try IdentityStore.generate(),
                localDevice: local,
                repository: repository,
                localOnly: true
            )
        )
        defer { manager.stop() }
        let port = try manager.startListening()
        XCTAssertTrue((5150...5169).contains(port))
        let payload = try manager.pairingPayload()
        XCTAssertEqual(payload.port, port)
        XCTAssertEqual(payload.deviceId, local.deviceId)
        let link = try payload.deepLink()
        XCTAssertTrue(link.hasPrefix("sefirah://pair?data="))
        let image = QrCodeImage.make(link)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 16)
    }
}
