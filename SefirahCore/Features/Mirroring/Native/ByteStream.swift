import Foundation
import Network

public enum StreamError: Error, Equatable, Sendable {
    case eof
    case cancelled
    case timeout
    case network(String)
    case closed
}

/// A connected byte stream (one scrcpy socket).
public protocol ByteStream: AnyObject, Sendable {
    /// Exactly `n` bytes, or throws `StreamError.eof` / `.cancelled` / `.network`.
    func readExactly(_ n: Int) async throws -> Data
    func write(_ data: Data) async throws
    func close()
}

public protocol StreamConnecting: Sendable {
    func connect(port: UInt16, noDelay: Bool) async throws -> any ByteStream
}

/// `NWConnection` to 127.0.0.1:port.
public final class NWByteStream: ByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "io.github.madeye.sefirah.mirror.stream")
    private let lock = NSLock()
    private var closed = false

    private init(connection: NWConnection) {
        self.connection = connection
    }

    public static func connect(port: UInt16, noDelay: Bool, timeout: TimeInterval = 5) async throws -> NWByteStream {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = noDelay
        tcp.connectionTimeout = Int(timeout)
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        let stream = NWByteStream(connection: connection)
        let once = ResumeOnce()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.run { continuation.resume() }
                    case .failed(let error):
                        once.run { continuation.resume(throwing: StreamError.network(error.localizedDescription)) }
                    case .waiting(let error):
                        // Local loopback: "waiting" means nobody listens; treat as failure so the caller retries.
                        connection.cancel()
                        once.run { continuation.resume(throwing: StreamError.network(error.localizedDescription)) }
                    case .cancelled:
                        once.run { continuation.resume(throwing: StreamError.cancelled) }
                    default:
                        break
                    }
                }
                connection.start(queue: stream.queue)
                stream.queue.asyncAfter(deadline: .now() + timeout) {
                    once.run {
                        connection.cancel()
                        continuation.resume(throwing: StreamError.timeout)
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
        connection.stateUpdateHandler = nil
        return stream
    }

    public func readExactly(_ n: Int) async throws -> Data {
        guard n > 0 else { return Data() }
        guard !isClosed else { throw StreamError.closed }
        let connection = self.connection
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: n, maximumLength: n) { content, _, isComplete, error in
                    if let content, content.count == n {
                        continuation.resume(returning: content)
                    } else if let error {
                        continuation.resume(throwing: Self.map(error))
                    } else if isComplete || content == nil || content!.count < n {
                        continuation.resume(throwing: StreamError.eof)
                    } else {
                        continuation.resume(throwing: StreamError.eof)
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    public func write(_ data: Data) async throws {
        guard !isClosed else { throw StreamError.closed }
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: Self.map(error)) } else { continuation.resume() }
            })
        }
    }

    public func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        if !wasClosed { connection.cancel() }
    }

    private var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    private static func map(_ error: NWError) -> StreamError {
        switch error {
        case .posix(let code) where code == .ECANCELED: return .cancelled
        case .posix(let code) where code == .ECONNRESET || code == .EPIPE || code == .ENOTCONN: return .eof
        default: return .network(error.localizedDescription)
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { body() }
        }
    }
}

public struct NWStreamConnector: StreamConnecting {
    public var timeout: TimeInterval = 5
    public init() {}
    public func connect(port: UInt16, noDelay: Bool) async throws -> any ByteStream {
        try await NWByteStream.connect(port: port, noDelay: noDelay, timeout: timeout)
    }
}
