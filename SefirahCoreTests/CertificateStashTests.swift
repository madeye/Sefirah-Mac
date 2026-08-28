import SefirahCore
import XCTest

final class CertificateStashTests: XCTestCase {
    func testStashAndTakeBySPKI() throws {
        let identity = try IdentityStore.generate()
        let stash = CertificateStash()
        stash.stash(certificateDER: identity.certificateDER)
        let taken = stash.take(publicKeyBase64: identity.publicKeyBase64)
        XCTAssertEqual(taken, identity.certificateDER)
        XCTAssertNil(stash.take(publicKeyBase64: identity.publicKeyBase64))
    }

    func testUnknownKeyReturnsNil() {
        let stash = CertificateStash()
        XCTAssertNil(stash.take(publicKeyBase64: "not-a-key"))
    }

    func testAuthFallsBackToPinnedCertificateWhenStashEmpty() throws {
        let identity = try IdentityStore.generate()
        let resolved = SessionAuthentication.certificate(
            publicKeyBase64: identity.publicKeyBase64,
            stashed: nil,
            pinned: identity.certificateDER,
            paired: nil
        )
        XCTAssertEqual(resolved, identity.certificateDER)
        XCTAssertTrue(SessionAuthentication.matches(identity.certificateDER, publicKeyBase64: identity.publicKeyBase64))
        let other = try IdentityStore.generate()
        XCTAssertNil(
            SessionAuthentication.certificate(
                publicKeyBase64: identity.publicKeyBase64,
                stashed: nil,
                pinned: other.certificateDER,
                paired: nil
            )
        )
    }
}
