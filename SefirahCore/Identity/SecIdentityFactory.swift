import CryptoKit
import Foundation
import Security

enum SecIdentityFactory {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var cache: [String: SecIdentity] = [:]
    }

    private static let state = State()

    static func makeIdentity(_ identity: DeviceIdentity) throws -> SecIdentity {
        state.lock.lock()
        defer { state.lock.unlock() }
        if let cached = state.cache[identity.publicKeyBase64] {
            return cached
        }
        let created = try create(identity)
        state.cache[identity.publicKeyBase64] = created
        return created
    }

    /// In-memory `SecIdentity` from cert DER + PKCS8 P-256 key.
    /// Avoids keychain import (`SecItemImport` of unencrypted PKCS8 returns
    /// `errSecPassphraseRequired` / -25260 on modern macOS, which blocked QR).
    private static func create(_ identity: DeviceIdentity) throws -> SecIdentity {
        guard let certificate = SecCertificateCreateWithData(nil, identity.certificateDER as CFData) else {
            throw IdentityError.invalidCertificate
        }

        let privateKey = try P256.Signing.PrivateKey(derRepresentation: identity.privateKeyDER)
        var createError: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
        ]
        guard let secKey = SecKeyCreateWithData(
            privateKey.x963Representation as CFData,
            attributes as CFDictionary,
            &createError
        ) else {
            throw IdentityError.missingPrivateKey
        }

        guard let secIdentity = SecIdentityCreate(nil, certificate, secKey) else {
            throw IdentityError.invalidCertificate
        }
        return secIdentity
    }
}
