import Darwin
import Foundation

public struct QrCodePayload: Codable, Sendable, Equatable {
    public var addresses: [String]
    public var port: Int
    public var deviceId: String
    public var deviceName: String

    public init(addresses: [String], port: Int, deviceId: String, deviceName: String) {
        self.addresses = addresses
        self.port = port
        self.deviceId = deviceId
        self.deviceName = deviceName
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SocketCodecError.invalidJSON
        }
        return json
    }

    /// `sefirah://pair?data=<url-encoded JSON>` matching C# `Uri.EscapeDataString`.
    public func deepLink() throws -> String {
        let json = try jsonString()
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = json.addingPercentEncoding(withAllowedCharacters: allowed) ?? json
        return "sefirah://pair?data=\(encoded)"
    }

    public static func parseDeepLink(_ link: String) throws -> QrCodePayload {
        guard let url = URL(string: link),
              url.scheme == "sefirah",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let data = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let jsonData = data.data(using: .utf8)
        else {
            throw SocketCodecError.invalidJSON
        }
        return try JSONDecoder().decode(QrCodePayload.self, from: jsonData)
    }
}

public enum LocalIPv4Addresses {
    public static func all() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(first) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let flags = Int32(interface.ifa_flags)
                if (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) != IFF_LOOPBACK {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        addresses.append(String(cString: hostname))
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return addresses
    }

    /// Subnet broadcast addresses (plus `255.255.255.255`) so phones on Wi-Fi see us.
    public static func broadcastAddresses() -> [String] {
        var addresses: [String] = ["255.255.255.255"]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return addresses }
        defer { freeifaddrs(first) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               (flags & IFF_UP) == IFF_UP,
               (flags & IFF_LOOPBACK) != IFF_LOOPBACK,
               (flags & IFF_BROADCAST) == IFF_BROADCAST,
               let broad = interface.ifa_dstaddr,
               broad.pointee.sa_family == UInt8(AF_INET)
            {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    broad,
                    socklen_t(broad.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    addresses.append(String(cString: hostname))
                }
            }
            pointer = interface.ifa_next
        }
        return addresses
    }
}
