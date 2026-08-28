import Foundation
import Network
import os

private let codecLog = Logger(subsystem: "io.github.madeye.sefirah.mac", category: "codec")

final class NDJSONConnection: @unchecked Sendable {
    let id: UUID
    let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private let lock = NSLock()
    private var cancelled = false

    var onMessage: ((SocketMessage) -> Void)?
    var onReady: (() -> Void)?
    var onFailed: ((Error?) -> Void)?

    init(connection: NWConnection, queue: DispatchQueue, id: UUID = UUID()) {
        self.connection = connection
        self.queue = queue
        self.id = id
    }

    var remoteHost: String {
        switch connection.currentPath?.remoteEndpoint {
        case .hostPort(let host, _):
            return canonicalHost("\(host)")
        default:
            return ""
        }
    }

    var remotePort: Int {
        switch connection.currentPath?.remoteEndpoint {
        case .hostPort(_, let port):
            return Int(port.rawValue)
        default:
            return 0
        }
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady?()
                self.receiveLoop()
            case .failed(let error):
                self.fail(error)
            case .cancelled:
                self.fail(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ message: SocketMessage) {
        do {
            let data = try NDJSONCodec.encodeLine(message)
            connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            fail(error)
        }
    }

    func cancel() {
        lock.lock()
        let already = cancelled
        cancelled = true
        lock.unlock()
        guard !already else { return }
        connection.cancel()
    }

    private func fail(_ error: Error?) {
        lock.lock()
        let already = cancelled
        cancelled = true
        lock.unlock()
        guard !already else { return }
        connection.cancel()
        onFailed?(error)
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                self.lock.lock()
                self.buffer.append(content)
                var buffer = self.buffer
                self.lock.unlock()
                // Skip unknown/unreadable lines. A single payload mismatch must not
                // kill the TLS session (Android sends extras after pair).
                for line in NDJSONCodec.popCompleteLines(from: &buffer) {
                    if let message = try? NDJSONCodec.decodeMessage(from: line) {
                        self.onMessage?(message)
                    } else {
                        let type = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["type"] as? String ?? "unknown"
                        codecLog.error("skipped \(type, privacy: .public)")
                    }
                }
                self.lock.lock()
                self.buffer = buffer
                self.lock.unlock()
            }
            if let error {
                self.fail(error)
                return
            }
            if isComplete {
                self.fail(nil)
                return
            }
            self.receiveLoop()
        }
    }
}
