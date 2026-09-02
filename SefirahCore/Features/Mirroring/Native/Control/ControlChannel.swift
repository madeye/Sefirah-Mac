import Foundation

/// Lock-protected send queue (no `await` on the input path) plus writer/reader tasks over the control socket.
public final class ControlChannel: @unchecked Sendable {
    public static let queueCapacity = 64

    private let lock = NSLock()
    private var queue: [ControlMessage] = []
    private var droppedCount = 0
    private let wake: AsyncStream<Void>
    private let wakeContinuation: AsyncStream<Void>.Continuation

    public init() {
        (wake, wakeContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Enqueues without blocking. When full, the oldest droppable message goes; a pending
    /// `resizeDisplay` is replaced by a newer one.
    public func send(_ message: ControlMessage) {
        lock.lock()
        if case .resizeDisplay = message, let i = queue.firstIndex(where: { if case .resizeDisplay = $0 { return true } else { return false } }) {
            queue[i] = message
        } else {
            if queue.count >= Self.queueCapacity {
                if let i = queue.firstIndex(where: \.isDroppable) {
                    queue.remove(at: i)
                    droppedCount += 1
                }
            }
            queue.append(message)
        }
        lock.unlock()
        wakeContinuation.yield()
    }

    /// Messages waiting to be written (tests).
    public var pending: [ControlMessage] { lock.lock(); defer { lock.unlock() }; return queue }
    public var dropped: Int { lock.lock(); defer { lock.unlock() }; return droppedCount }

    private func drain() -> [ControlMessage] {
        lock.lock(); defer { lock.unlock() }
        let all = queue
        queue.removeAll(keepingCapacity: true)
        return all
    }

    /// Runs until the stream ends or the task is cancelled. Delivers device messages via `onMessage`.
    public func run(stream: any ByteStream, onMessage: @escaping @Sendable (DeviceMessage) -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.writer(stream) }
            group.addTask { try await Self.reader(stream, onMessage: onMessage) }
            try await group.next()
            group.cancelAll()
        }
    }

    private func writer(_ stream: any ByteStream) async throws {
        // Flush anything queued before the socket was up.
        for message in drain() { try await stream.write(message.encode()) }
        for await _ in wake {
            try Task.checkCancellation()
            for message in drain() { try await stream.write(message.encode()) }
        }
    }

    private static func reader(_ stream: any ByteStream, onMessage: @escaping @Sendable (DeviceMessage) -> Void) async throws {
        var buffer = Data()
        while true {
            // Read the type byte, then whatever the message needs, using the incremental parser.
            buffer.append(try await stream.readExactly(1))
            while true {
                if let (message, consumed) = try DeviceMessage.parse(buffer) {
                    onMessage(message)
                    buffer.removeFirst(consumed)
                    if buffer.isEmpty { break }
                } else {
                    buffer.append(try await stream.readExactly(Self.needed(buffer)))
                }
            }
        }
    }

    /// Bytes to read next so the parser can make progress on a partial message.
    static func needed(_ buffer: Data) -> Int {
        guard let type = buffer.first else { return 1 }
        switch type {
        case 0:
            if buffer.count < 5 { return 5 - buffer.count }
            return 5 + Int(BigEndian.u32(buffer, at: 1)) - buffer.count
        case 1:
            return 9 - buffer.count
        case 2:
            if buffer.count < 5 { return 5 - buffer.count }
            return 5 + Int(BigEndian.u16(buffer, at: 3)) - buffer.count
        default:
            return 1
        }
    }
}
