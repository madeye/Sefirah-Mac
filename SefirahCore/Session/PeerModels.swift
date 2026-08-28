import Foundation

public struct DiscoveredPeer: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var model: String
    public var address: String
    public var port: Int
    public var certificateDER: Data
    public var verificationKey: String
    public var isPairing: Bool

    public init(
        id: String,
        name: String,
        model: String,
        address: String,
        port: Int,
        certificateDER: Data,
        verificationKey: String,
        isPairing: Bool = false
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.address = address
        self.port = port
        self.certificateDER = certificateDER
        self.verificationKey = verificationKey
        self.isPairing = isPairing
    }
}

public struct ConnectedPeer: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var model: String
    public var address: String
    public var port: Int
    public var certificateDER: Data
    public var isConnected: Bool

    public init(
        id: String,
        name: String,
        model: String,
        address: String,
        port: Int,
        certificateDER: Data,
        isConnected: Bool
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.address = address
        self.port = port
        self.certificateDER = certificateDER
        self.isConnected = isConnected
    }
}

public enum SessionEvent: Sendable, Equatable {
    case discovered(DiscoveredPeer)
    case pairingRequested(DiscoveredPeer)
    case paired(ConnectedPeer)
    case connected(ConnectedPeer)
    case disconnected(deviceId: String, forced: Bool)
    case inboundMessage(deviceId: String, SocketMessage)
}

func canonicalHost(_ host: String) -> String {
    PeerAddress.normalize(host)
}

public enum PeerAddress {
    /// Strip IPv6 brackets, zone ids, and IPv4-mapped prefixes.
    public static func normalize(_ host: String) -> String {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("[") && host.contains("]") {
            let inner = host.dropFirst()
            if let end = inner.firstIndex(of: "]") {
                host = String(inner[..<end])
            }
        }
        if let percent = host.firstIndex(of: "%") {
            host = String(host[..<percent])
        }
        if host.lowercased().hasPrefix("::ffff:") {
            host = String(host.dropFirst(7))
        }
        return host
    }

    /// Addresses we can use to reconnect. Drops loopback and IPv6 link-local (`fe80::`).
    public static func reconnectable(_ host: String) -> String? {
        let host = normalize(host)
        guard !host.isEmpty else { return nil }
        if host == "127.0.0.1" || host == "::1" || host.hasPrefix("127.") { return nil }
        let lowered = host.lowercased()
        if lowered.hasPrefix("fe80:") || lowered == "fe80::" { return nil }
        return host
    }
}
