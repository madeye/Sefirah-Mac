import CryptoKit
import Foundation
import Security
import X509

/// First-connect cert stash. Matches C# `SslHelper` (~30s TTL keyed by Base64 SPKI).
public final class CertificateStash: @unchecked Sendable {
    public static let timeToLive: TimeInterval = 30

    private struct Entry {
        var certificateDER: Data
        var storedAt: Date
    }

    private let lock = NSLock()
    private var queues: [String: [Entry]] = [:]

    public init() {}

    public func stash(certificateDER: Data) {
        guard let spki = try? PeerCertificate.spki(fromCertificateDER: certificateDER) else { return }
        let key = spki.base64EncodedString()
        lock.lock()
        defer { lock.unlock() }
        purgeLocked(now: Date())
        queues[key, default: []].append(Entry(certificateDER: certificateDER, storedAt: Date()))
    }

    public func take(publicKeyBase64: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        purgeLocked(now: Date())
        guard var queue = queues[publicKeyBase64], !queue.isEmpty else { return nil }
        let entry = queue.removeFirst()
        if queue.isEmpty {
            queues.removeValue(forKey: publicKeyBase64)
        } else {
            queues[publicKeyBase64] = queue
        }
        return entry.certificateDER
    }

    private func purgeLocked(now: Date) {
        for (key, queue) in queues {
            let fresh = queue.filter { now.timeIntervalSince($0.storedAt) <= Self.timeToLive }
            if fresh.isEmpty {
                queues.removeValue(forKey: key)
            } else {
                queues[key] = fresh
            }
        }
    }
}

/// Resolves the peer certificate for an `Authentication` message.
/// Outbound pin-mode TLS does not populate the first-connect stash, so we
/// fall back to the pinned/paired DER when its SPKI matches `publicKey`.
public enum SessionAuthentication {
    public static func certificate(
        publicKeyBase64: String,
        stashed: Data?,
        pinned: Data?,
        paired: Data?
    ) -> Data? {
        if let stashed, !stashed.isEmpty, matches(stashed, publicKeyBase64: publicKeyBase64) {
            return stashed
        }
        if let pinned, !pinned.isEmpty, matches(pinned, publicKeyBase64: publicKeyBase64) {
            return pinned
        }
        if let paired, !paired.isEmpty, matches(paired, publicKeyBase64: publicKeyBase64) {
            return paired
        }
        if let stashed, !stashed.isEmpty { return stashed }
        return nil
    }

    public static func matches(_ certificateDER: Data, publicKeyBase64: String) -> Bool {
        guard let spki = try? PeerCertificate.spki(fromCertificateDER: certificateDER) else { return false }
        return spki.base64EncodedString() == publicKeyBase64
    }
}

enum PeerCertificate {
    static func der(from secTrust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
              let peer = chain.first
        else { return nil }
        return SecCertificateCopyData(peer) as Data
    }

    static func spki(fromCertificateDER der: Data) throws -> Data {
        let certificate = try Certificate(derEncoded: Array(der))
        guard let publicKey = P256.Signing.PublicKey(certificate.publicKey) else {
            throw IdentityError.invalidCertificate
        }
        return publicKey.derRepresentation
    }
}
