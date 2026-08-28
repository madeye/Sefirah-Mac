import Foundation
import Network
import Security

/// TLS data-plane client for inbound `FileTransferInfo`.
/// Connects to `serverInfo.port` with the pinned peer certificate, then runs `FileTransferSession`.
public enum FileTransferClient {
    public static func receive(
        files: [FileMetadata],
        destination: URL,
        host: String,
        port: Int,
        identity: DeviceIdentity,
        pinnedCertificateDER: Data
    ) async throws -> [URL] {
        let secIdentity = try SecIdentityFactory.makeIdentity(identity)
        let queue = DispatchQueue(label: "io.github.madeye.sefirah.xfer")
        let stash = CertificateStash()
        let parameters = TLSFactory.parameters(
            identity: secIdentity,
            policy: .pin(pinnedCertificateDER),
            stash: stash,
            queue: queue
        )
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw POSIXError(.ECONNREFUSED)
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        return try await receive(files: files, destination: destination, connection: connection, queue: queue)
    }

    /// Shared receive loop used by the TLS client and loopback tests.
    public static func receive(
        files: [FileMetadata],
        destination: URL,
        connection: NWConnection,
        queue: DispatchQueue
    ) async throws -> [URL] {
        try await waitReady(connection, queue: queue)
        defer { connection.cancel() }
        return try await FileTransferSession.receive(
            files: files,
            destination: destination,
            io: NWFileTransferIO(connection: connection)
        )
    }

    private static func waitReady(_ connection: NWConnection, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OnceResume(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resumeSuccess()
                case .failed(let error):
                    once.resumeFailure(error)
                case .cancelled:
                    once.resumeFailure(CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}

private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resumeSuccess() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }

    func resumeFailure(_ error: Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}

final class NWFileTransferIO: FileTransferIO, @unchecked Sendable {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func read(maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let content, !content.isEmpty {
                    continuation.resume(returning: content)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: FileTransferError.unexpectedEOF)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}
