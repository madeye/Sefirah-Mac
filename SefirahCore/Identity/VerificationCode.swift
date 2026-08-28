import CryptoKit
import Foundation

/// Pairing PIN shown on both devices. Must match C# `SslHelper.GetVerificationCode`:
/// unsigned-byte-sorted concat of the two SPKIs → SHA-256 → first 8 hex chars, uppercase.
/// Empty peer SPKI returns `00000000` without hashing.
public enum VerificationCode {
    public static let emptyPeerFallback = "00000000"

    public static func compute(localSPKI: Data, peerSPKI: Data) -> String {
        if peerSPKI.isEmpty { return emptyPeerFallback }
        let concat = sortedConcatUnsigned(localSPKI, peerSPKI)
        let digest = SHA256.hash(data: concat)
        return digest.prefix(4).map { String(format: "%02X", $0) }.joined()
    }

    public static func compute(localSPKI: Data, peerPublicKeyBase64: String) -> String {
        let peer = Data(base64Encoded: peerPublicKeyBase64) ?? Data()
        return compute(localSPKI: localSPKI, peerSPKI: peer)
    }

    /// When `a < b` (unsigned), returns `b‖a`; otherwise `a‖b`.
    public static func sortedConcatUnsigned(_ a: Data, _ b: Data) -> Data {
        compareUnsigned(a, b) < 0 ? b + a : a + b
    }

    public static func compareUnsigned(_ a: Data, _ b: Data) -> Int {
        let aBytes = [UInt8](a)
        let bBytes = [UInt8](b)
        let count = min(aBytes.count, bBytes.count)
        for index in 0..<count {
            if aBytes[index] != bBytes[index] {
                return aBytes[index] < bBytes[index] ? -1 : 1
            }
        }
        if aBytes.count == bBytes.count { return 0 }
        return aBytes.count < bBytes.count ? -1 : 1
    }
}
