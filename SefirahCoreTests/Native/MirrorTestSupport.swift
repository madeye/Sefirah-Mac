import CoreMedia
import Foundation
@testable import SefirahCore
import XCTest

/// Scripted in-memory socket: `feed` bytes, `finish` for EOF; records writes.
final class MemoryByteStream: ByteStream, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false
    private var closedFlag = false
    private var waiter: (n: Int, continuation: CheckedContinuation<Data, Error>)?
    private(set) var written = Data()
    let name: String

    init(_ data: Data = Data(), finished: Bool = false, name: String = "stream") {
        buffer = data
        self.finished = finished
        self.name = name
    }

    var isClosed: Bool { lock.withLock { closedFlag } }

    func feed(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
        serve()
    }

    func finish() {
        lock.withLock { finished = true }
        serve()
    }

    private func serve() {
        lock.lock()
        guard let waiter else { lock.unlock(); return }
        if buffer.count >= waiter.n {
            let out = buffer.prefix(waiter.n)
            buffer.removeFirst(waiter.n)
            self.waiter = nil
            lock.unlock()
            waiter.continuation.resume(returning: Data(out))
        } else if finished || closedFlag {
            self.waiter = nil
            let error: StreamError = closedFlag ? .cancelled : .eof
            lock.unlock()
            waiter.continuation.resume(throwing: error)
        } else {
            lock.unlock()
        }
    }

    func readExactly(_ n: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if closedFlag {
                    lock.unlock()
                    continuation.resume(throwing: StreamError.cancelled)
                } else if buffer.count >= n {
                    let out = buffer.prefix(n)
                    buffer.removeFirst(n)
                    lock.unlock()
                    continuation.resume(returning: Data(out))
                } else if finished {
                    lock.unlock()
                    continuation.resume(throwing: StreamError.eof)
                } else {
                    waiter = (n, continuation)
                    lock.unlock()
                }
            }
        } onCancel: {
            close()
        }
    }

    func write(_ data: Data) async throws {
        lock.withLock { written.append(data) }
    }

    func close() {
        lock.withLock { closedFlag = true }
        serve()
    }
}

final class ScriptedConnector: StreamConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [MemoryByteStream]
    private(set) var connects: [(port: UInt16, noDelay: Bool)] = []

    init(_ streams: [MemoryByteStream]) { self.streams = streams }

    func connect(port: UInt16, noDelay: Bool) async throws -> any ByteStream {
        let next: MemoryByteStream? = lock.withLock {
            connects.append((port, noDelay))
            return streams.isEmpty ? nil : streams.removeFirst()
        }
        guard let next else { throw StreamError.network("no more scripted streams") }
        return next
    }
}

final class FakeServerProcess: ServerProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    var tail = ""
    private(set) var terminated = false
    let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    var isRunning: Bool { lock.withLock { status == nil } }
    var exitStatus: Int32? { lock.withLock { status } }
    var logTail: String { lock.withLock { tail } }

    func emit(_ line: String) {
        lock.withLock { tail += line + "\n" }
        onLine(line)
    }

    func exit(_ code: Int32) { lock.withLock { status = code } }

    func terminate() {
        lock.withLock { terminated = true; if status == nil { status = -15 } }
    }

    func waitForExit(timeout: TimeInterval) async -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let s = exitStatus { return s }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return exitStatus
    }
}

final class FakeSpawner: DetachedProcessSpawning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var spawned: [(executable: URL, arguments: [String])] = []
    private(set) var processes: [FakeServerProcess] = []
    var failWith: Error?

    func spawn(_ executable: URL, _ arguments: [String], environment: [String: String],
               onLine: @escaping @Sendable (String) -> Void) throws -> any ServerProcess
    {
        if let failWith { throw failWith }
        let process = FakeServerProcess(onLine: onLine)
        lock.withLock {
            spawned.append((executable, arguments))
            processes.append(process)
        }
        return process
    }

    var last: FakeServerProcess? { lock.withLock { processes.last } }
}

final class RecordingVideoSink: VideoFrameSink, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var formats: [(width: Int, height: Int)] = []
    private(set) var samples: [(pts: Int64, keyFrame: Bool, bytes: Int)] = []
    private(set) var flushes = 0
    var requiresFlushOnce = false
    var failure: String?
    var onSample: (@Sendable () -> Void)?
    /// Number of upcoming non-keyframe samples to reject (simulates a renderer that is not draining).
    var dropNextInterFrames = 0
    private(set) var dropped = 0

    func formatChanged(_ format: CMFormatDescription, width: Int, height: Int) {
        lock.withLock { formats.append((width, height)) }
    }

    @discardableResult
    func enqueue(_ sample: CMSampleBuffer, keyFrame: Bool) -> Bool {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let accepted: Bool = lock.withLock {
            if !keyFrame, dropNextInterFrames > 0 {
                dropNextInterFrames -= 1
                dropped += 1
                return false
            }
            samples.append((pts.value, keyFrame, CMSampleBufferGetTotalSampleSize(sample)))
            return true
        }
        onSample?()
        return accepted
    }

    var requiresFlush: Bool {
        lock.withLock {
            let v = requiresFlushOnce
            requiresFlushOnce = false
            return v
        }
    }

    func flush() { lock.withLock { flushes += 1 } }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [MirrorEvent] = []
    var all: [MirrorEvent] { lock.withLock { events } }
    func append(_ e: MirrorEvent) { lock.withLock { events.append(e) } }

    var states: [MirrorState] {
        all.compactMap { if case .state(let s) = $0 { return s } else { return nil } }
    }

    var serverLogs: [String] {
        all.compactMap { if case .serverLog(let s) = $0 { return s } else { return nil } }
    }
}

enum Hex {
    static func data(_ hex: String) -> Data {
        let clean = hex.filter { !$0.isWhitespace && $0 != "|" }
        var out = Data(capacity: clean.count / 2)
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            out.append(UInt8(clean[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    static func string(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}

/// Fixtures captured from the Xiaomi 14 Ultra (scrcpy-server 4.1, max_size=1280, H.264 / H.265).
enum Fixtures {
    static let deviceName = "24031PN0DC"
    /// 64-byte device meta.
    static var deviceMeta: Data {
        var d = Data(deviceName.utf8)
        d.append(Data(repeating: 0, count: 64 - d.count))
        return d
    }

    static let h264Config = Hex.data(FixtureBytes.h264Config)
    static let h265Config = Hex.data(FixtureBytes.h265Config)
    /// A keyframe access unit that decodes with `h264Config` (IDR NAL, possibly truncated is fine for CMSampleBuffer creation).
    static let h264KeyFrame = Hex.data(FixtureBytes.h264KeyFramePrefix)

    static func packet(pts: UInt64, config: Bool = false, keyFrame: Bool = false, payload: Data) -> Data {
        var flags: UInt64 = config ? MediaPacketHeader.flagConfig : pts & MediaPacketHeader.ptsMask
        if keyFrame { flags |= MediaPacketHeader.flagKeyFrame }
        var d = Data()
        BigEndian.append(flags, to: &d)
        BigEndian.append(UInt32(payload.count), to: &d)
        d.append(payload)
        return d
    }

    static func session(width: UInt32, height: UInt32, clientResized: Bool = false) -> Data {
        var d = Data()
        BigEndian.append(UInt32(0x8000_0000) | (clientResized ? 1 : 0), to: &d)
        BigEndian.append(width, to: &d)
        BigEndian.append(height, to: &d)
        return d
    }

    static func codecID(_ raw: UInt32) -> Data {
        var d = Data()
        BigEndian.append(raw, to: &d)
        return d
    }
}

final class RecordingAudioSink: AudioSink, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var configured: [(codec: StreamCodecID, config: Data?)] = []
    private(set) var packets: [Data] = []
    private(set) var stops = 0
    var onPacket: (@Sendable () -> Void)?

    func configure(codec: StreamCodecID, config: Data?) { lock.withLock { configured.append((codec, config)) } }
    func enqueue(packet: Data) { lock.withLock { packets.append(packet) }; onPacket?() }
    func stop() { lock.withLock { stops += 1 } }
}
