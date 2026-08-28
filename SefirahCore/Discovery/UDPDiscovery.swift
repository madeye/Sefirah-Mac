import Darwin
import Foundation

public final class UDPDiscovery: @unchecked Sendable {
    public let port: UInt16
    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue: DispatchQueue
    private let localDeviceId: String
    public var onBroadcast: ((UdpBroadcast, String) -> Void)?

    public init(port: UInt16 = UInt16(SefirahConstants.Ports.discovery), localDeviceId: String, queue: DispatchQueue) {
        self.port = port
        self.localDeviceId = localDeviceId
        self.queue = queue
    }

    public func start() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError.fromErrno() }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw POSIXError.fromErrno()
        }

        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        socketFD = -1
    }

    public func send(_ broadcast: UdpBroadcast, to hosts: [String]) {
        // Android `readLine()` on the datagram; include the NDJSON newline.
        guard socketFD >= 0, let data = try? NDJSONCodec.encodeLine(.udpBroadcast(broadcast)) else { return }
        for host in hosts {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            inet_pton(AF_INET, host, &addr.sin_addr)
            _ = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, (data as NSData).bytes, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    public func broadcast(_ message: UdpBroadcast) {
        var hosts = LocalIPv4Addresses.all()
        hosts.append(contentsOf: LocalIPv4Addresses.broadcastAddresses())
        hosts.append("255.255.255.255")
        send(message, to: Array(Set(hosts)))
    }

    public static func parseBroadcast(_ data: Data) -> UdpBroadcast? {
        if let message = try? NDJSONCodec.decodeMessage(from: data),
           case .udpBroadcast(let broadcast) = message
        {
            return broadcast
        }
        // C# `Serialize(udpBroadcast)` as the concrete type may omit `type`.
        return try? JSONDecoder().decode(UdpBroadcast.self, from: data)
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var sender = sockaddr_in()
        var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &sender) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(socketFD, &buffer, buffer.count, 0, $0, &senderLength)
            }
        }
        guard count > 0 else { return }
        let data = Data(buffer.prefix(count))
        guard let broadcast = Self.parseBroadcast(data),
              broadcast.deviceId != localDeviceId
        else { return }
        var host = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &sender.sin_addr, &host, socklen_t(INET_ADDRSTRLEN))
        onBroadcast?(broadcast, String(cString: host))
    }
}

private extension POSIXError {
    static func fromErrno() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
