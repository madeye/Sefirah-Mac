import CryptoKit
import Foundation
import SwiftASN1
import X509

public struct DeviceIdentity: Sendable, Equatable {
    public let certificateDER: Data
    public let privateKeyDER: Data
    public let spki: Data

    public var publicKeyBase64: String {
        spki.base64EncodedString()
    }

    public func verificationCode(peerPublicKeyBase64: String) -> String {
        VerificationCode.compute(localSPKI: spki, peerPublicKeyBase64: peerPublicKeyBase64)
    }

    public func verificationCode(peerSPKI: Data) -> String {
        VerificationCode.compute(localSPKI: spki, peerSPKI: peerSPKI)
    }
}

public enum IdentityError: Error, Equatable, CustomStringConvertible {
    case missingPrivateKey
    case invalidCertificate
    case writeFailed
    case keychain(OSStatus)

    public var description: String {
        switch self {
        case .missingPrivateKey: "Identity private key is missing or unreadable"
        case .invalidCertificate: "Identity certificate is missing or unreadable"
        case .writeFailed: "Failed to persist identity files"
        case .keychain(let status): "Keychain error \(status)"
        }
    }
}

/// File-backed ECDSA P-256 identity (`CN=SefirahCastle`), the Mac equivalent of `Sefirah.pfx`.
public struct IdentityStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var certificateURL: URL {
        directory.appendingPathComponent(SefirahConstants.certificateFileName)
    }

    public var privateKeyURL: URL {
        directory.appendingPathComponent(SefirahConstants.privateKeyFileName)
    }

    public func loadOrCreate() throws -> DeviceIdentity {
        if let existing = try? load() {
            return existing
        }
        let created = try Self.generate()
        try persist(created)
        return created
    }

    public func load() throws -> DeviceIdentity {
        let certData = try Data(contentsOf: certificateURL)
        let keyData = try Data(contentsOf: privateKeyURL)
        guard !certData.isEmpty else { throw IdentityError.invalidCertificate }
        guard !keyData.isEmpty else { throw IdentityError.missingPrivateKey }
        let privateKey = try P256.Signing.PrivateKey(derRepresentation: keyData)
        _ = try Certificate(derEncoded: Array(certData))
        return DeviceIdentity(
            certificateDER: certData,
            privateKeyDER: keyData,
            spki: privateKey.publicKey.derRepresentation
        )
    }

    public static func generate() throws -> DeviceIdentity {
        let swiftCryptoKey = P256.Signing.PrivateKey()
        let key = Certificate.PrivateKey(swiftCryptoKey)
        let name = try DistinguishedName {
            CommonName(SefirahConstants.certificateCommonName)
        }
        let now = Date()
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true, keyEncipherment: true, dataEncipherment: true))
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: key.publicKey,
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: key
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let certificateDER = Data(serializer.serializedBytes)
        return DeviceIdentity(
            certificateDER: certificateDER,
            privateKeyDER: swiftCryptoKey.derRepresentation,
            spki: swiftCryptoKey.publicKey.derRepresentation
        )
    }

    private func persist(_ identity: DeviceIdentity) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try identity.certificateDER.write(to: certificateURL, options: .atomic)
            try identity.privateKeyDER.write(to: privateKeyURL, options: .atomic)
        } catch {
            throw IdentityError.writeFailed
        }
    }
}
