import CoreMedia
import Foundation

/// One native mirror session: push → tunnel → spawn → sockets → stream tasks → teardown.
public actor MirrorSession {
    public struct Timeouts: Sendable {
        public var dummyByteTotal: TimeInterval = 10
        public var dummyByteRetryDelay: TimeInterval = 0.1
        public var dummyByteMaxAttempts = 100
        public var deviceMeta: TimeInterval = 5
        public var header: TimeInterval = 5
        public var exitWait: TimeInterval = 1
        public init() {}
    }

    /// Lock-protected state that non-actor code (input path, emergencyStop) reads.
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var _videoSize: (Int, Int)?
        private var _stopping = false
        private var _streams: [any ByteStream] = []
        private var _process: (any ServerProcess)?
        private var _forwardPort: UInt16?
        private var _versionMismatch: String?

        var videoSize: (Int, Int)? {
            get { lock.withLock { _videoSize } }
            set { lock.withLock { _videoSize = newValue } }
        }
        var stopping: Bool {
            get { lock.withLock { _stopping } }
            set { lock.withLock { _stopping = newValue } }
        }
        var streams: [any ByteStream] { lock.withLock { _streams } }
        func addStream(_ s: any ByteStream) { lock.withLock { _streams.append(s) } }
        var process: (any ServerProcess)? {
            get { lock.withLock { _process } }
            set { lock.withLock { _process = newValue } }
        }
        var forwardPort: UInt16? {
            get { lock.withLock { _forwardPort } }
            set { lock.withLock { _forwardPort = newValue } }
        }
        var versionMismatch: String? {
            get { lock.withLock { _versionMismatch } }
            set { lock.withLock { _versionMismatch = newValue } }
        }
    }

    public let config: MirrorSessionConfig
    private let launcher: ServerLauncher
    private let connector: any StreamConnecting
    private let videoSink: any VideoFrameSink
    private let audioSink: (any AudioSink)?
    private let events: @Sendable (MirrorEvent) -> Void
    private let timeouts: Timeouts
    private let shared = Shared()
    public nonisolated let control = ControlChannel()

    private var state: MirrorState = .idle
    private var runTask: Task<Void, Never>?
    private var finished = false

    public init(
        config: MirrorSessionConfig,
        launcher: ServerLauncher,
        connector: any StreamConnecting = NWStreamConnector(),
        videoSink: any VideoFrameSink,
        audioSink: (any AudioSink)? = nil,
        timeouts: Timeouts = Timeouts(),
        events: @escaping @Sendable (MirrorEvent) -> Void
    ) {
        self.config = config
        self.launcher = launcher
        self.connector = connector
        self.videoSink = videoSink
        self.audioSink = audioSink
        self.timeouts = timeouts
        self.events = events
    }

    /// Last session packet's size, for stamping input events.
    public nonisolated var currentVideoSize: (width: Int, height: Int)? {
        shared.videoSize
    }

    public var currentState: MirrorState { state }

    /// Returns when streaming ends (stopped or failed); never throws.
    public func start() async {
        guard runTask == nil else { await runTask?.value; return }
        let task = Task { [self] in
            var failure: MirrorError?
            do {
                try await run()
            } catch let error as MirrorError {
                failure = error
            } catch is CancellationError {
                failure = .cancelled
            } catch let error as StreamError {
                failure = error == .cancelled ? .cancelled : .connectionLost
            } catch {
                failure = .protocolError(String(describing: error))
            }
            setState(.stopping)
            await teardown()
            if isStopping || failure == .cancelled {
                setState(.idle)
            } else if let failure {
                setState(.failed(failure))
            } else {
                setState(.idle)
            }
            finished = true
        }
        runTask = task
        await task.value
    }

    /// Idempotent; closes sockets, cancels the stream tasks and waits for teardown.
    public func stop() async {
        shared.stopping = true
        closeStreams()
        runTask?.cancel()
        await runTask?.value
    }

    /// Synchronous best effort for app quit: close sockets (the server exits on EPIPE) and terminate adb.
    public nonisolated func emergencyStop() {
        shared.stopping = true
        shared.streams.forEach { $0.close() }
        shared.process?.terminate()
    }

    // MARK: - Lifecycle

    private var isStopping: Bool { shared.stopping }

    private func setState(_ new: MirrorState) {
        state = new
        events(.state(new))
    }

    private nonisolated func closeStreams() {
        shared.streams.forEach { $0.close() }
    }

    private func register(_ stream: any ByteStream) {
        shared.addStream(stream)
    }

    private func run() async throws {
        let serial = config.serial
        let options = config.options

        if !config.unlockCommands.isEmpty {
            setState(.preparing(.unlock))
            for entry in config.unlockCommands {
                try Task.checkCancellation()
                let command = entry.command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else { continue }
                if command.contains("%pwd%") {
                    events(.warning("Unlock command with %pwd% skipped (password prompt not supported yet)"))
                    continue
                }
                do {
                    let result = try await launcher.shell(serial: serial, command, timeout: config.unlockTimeout)
                    if result.exitCode != 0 {
                        events(.warning("Unlock command \"\(command)\" exited \(result.exitCode)"))
                    }
                } catch {
                    events(.warning("Unlock command \"\(command)\" failed: \(error)"))
                }
                if entry.delayMs > 0 { try await Task.sleep(nanoseconds: UInt64(entry.delayMs) * 1_000_000) }
            }
        }

        setState(.preparing(.push))
        do { try await launcher.push(serial: serial) } catch let e as AdbError { throw MirrorError.adb(e) }
        try Task.checkCancellation()

        setState(.preparing(.tunnel))
        let port: UInt16
        do { port = try await launcher.forward(serial: serial, socketName: options.socketName) } catch let e as AdbError { throw MirrorError.adb(e) }
        shared.forwardPort = port
        try Task.checkCancellation()

        setState(.preparing(.spawn))
        let process: any ServerProcess
        do {
            let shared = self.shared
            let events = self.events
            process = try launcher.spawn(serial: serial, options: options) { line in
                if line.contains("does not match the client") { shared.versionMismatch = line }
                events(.serverLog(line))
            }
        } catch let e as MirrorError {
            throw e
        } catch {
            throw MirrorError.serverSpawnFailed(error.localizedDescription)
        }
        shared.process = process

        setState(.connecting)
        // a. First enabled socket: connect until the dummy byte arrives.
        let first = try await connectFirst(port: port, process: process)
        register(first)
        // b. Remaining sockets in order video, audio, control (no dummy byte).
        var video: (any ByteStream)? = options.video ? first : nil
        var audio: (any ByteStream)? = nil
        var controlStream: (any ByteStream)? = nil
        if options.audio {
            if video == nil { audio = first } else { audio = try await connector.connect(port: port, noDelay: false); register(audio!) }
        }
        if options.control {
            if video == nil, audio == nil { controlStream = first } else { controlStream = try await connector.connect(port: port, noDelay: true); register(controlStream!) }
        }
        // c. Tunnel no longer needed.
        await launcher.removeForward(serial: serial, port: port)
        shared.forwardPort = nil
        // d. Device meta (only sent after all sockets are accepted).
        let meta = try await withTimeout(timeouts.deviceMeta, stage: .deviceMeta) { try await first.readExactly(64) }
        let name = String(decoding: meta.prefix { $0 != 0 }, as: UTF8.self)
        events(.deviceName(name))

        setState(.streaming)
        for action in config.actions {
            switch action {
            case .displayPower(let on): control.send(.setDisplayPower(on: on))
            case .uhidKeyboard: control.send(.uhidCreate(id: 1, vendorId: 0, productId: 0, name: "", descriptor: HidKeyboard.descriptor))
            case .startApp(let package): control.send(.startApp(package))
            }
        }

        let videoSink = self.videoSink, audioSink = self.audioSink, events = self.events, shared = self.shared
        let control = self.control, timeouts = self.timeouts
        try await withThrowingTaskGroup(of: Void.self) { group in
            if let video {
                group.addTask { try await Self.runVideo(video, sink: videoSink, control: control, shared: shared, timeouts: timeouts, events: events) }
            }
            if let audio {
                group.addTask { try await Self.runAudio(audio, sink: audioSink, timeouts: timeouts, events: events) }
            }
            if let controlStream {
                group.addTask {
                    try await control.run(stream: controlStream) { message in
                        switch message {
                        case .clipboard(let text): events(.clipboard(text))
                        case .ackClipboard(let seq): events(.clipboardAck(seq))
                        case .uhidOutput(let id, let data): events(.uhidOutput(id: id, data: data))
                        }
                    }
                    throw MirrorError.connectionLost
                }
            }
            group.addTask {
                while process.isRunning {
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                if shared.stopping { throw CancellationError() }
                // Give the readers a moment to surface EOF first (nicer error), then report the exit.
                try await Task.sleep(nanoseconds: 300_000_000)
                throw MirrorError.serverExited(code: process.exitStatus ?? -1, log: process.logTail)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func connectFirst(port: UInt16, process: any ServerProcess) async throws -> any ByteStream {
        let deadline = Date().addingTimeInterval(timeouts.dummyByteTotal)
        var attempts = 0
        while true {
            try Task.checkCancellation()
            if !process.isRunning {
                if let mismatch = shared.versionMismatch { throw MirrorError.versionMismatch(mismatch) }
                throw MirrorError.serverExited(code: process.exitStatus ?? -1, log: process.logTail)
            }
            attempts += 1
            if attempts > timeouts.dummyByteMaxAttempts || Date() > deadline {
                throw MirrorError.handshakeTimeout(.dummyByte)
            }
            let stream: any ByteStream
            do {
                stream = try await connector.connect(port: port, noDelay: config.options.video ? false : true)
            } catch StreamError.cancelled {
                throw CancellationError()
            } catch {
                try await Task.sleep(nanoseconds: UInt64(timeouts.dummyByteRetryDelay * 1_000_000_000))
                continue
            }
            do {
                let remaining = max(0.05, deadline.timeIntervalSinceNow)
                _ = try await withTimeout(remaining, stage: .dummyByte) { try await stream.readExactly(1) }
                return stream
            } catch StreamError.eof {
                stream.close()
                try await Task.sleep(nanoseconds: UInt64(timeouts.dummyByteRetryDelay * 1_000_000_000))
            } catch StreamError.network {
                stream.close()
                try await Task.sleep(nanoseconds: UInt64(timeouts.dummyByteRetryDelay * 1_000_000_000))
            } catch {
                stream.close()
                throw error
            }
        }
    }

    private func teardown() async {
        closeStreams()
        let process = shared.process
        let port = shared.forwardPort
        shared.forwardPort = nil
        if let process {
            if await process.waitForExit(timeout: timeouts.exitWait) == nil { process.terminate() }
        }
        await launcher.killServer(serial: config.serial, scid: config.options.scid)
        if let port { await launcher.removeForward(serial: config.serial, port: port) }
        videoSink.flush()
        audioSink?.stop()
    }

    // MARK: - Stream loops (nonisolated: run off the actor)

    private static func runVideo(
        _ stream: any ByteStream, sink: any VideoFrameSink, control: ControlChannel, shared: Shared,
        timeouts: Timeouts, events: @escaping @Sendable (MirrorEvent) -> Void
    ) async throws {
        let codecRaw = BigEndian.u32(try await withTimeout(timeouts.header, stage: .videoHeader) { try await stream.readExactly(4) }, at: 0)
        let codec = StreamCodecID(rawValue: codecRaw)
        switch codec {
        case .h264, .h265: break
        case .av1:
            guard VideoFormat.av1Supported else { throw MirrorError.unsupportedVideoCodec(codecRaw) }
        case .disabled, .configError: throw MirrorError.videoConfigError
        default: throw MirrorError.unsupportedVideoCodec(codecRaw)
        }
        events(.videoCodec(codec))

        var header = try await withTimeout(timeouts.header, stage: .videoHeader) { try await stream.readExactly(12) }
        guard SessionHeader.isSession(header) else { throw MirrorError.protocolError("first video packet is not a session packet") }
        var session: SessionHeader
        do { session = try SessionHeader.parse(header) } catch { throw MirrorError.protocolError("bad session packet: \(error)") }
        shared.videoSize = (session.width, session.height)
        events(.videoSize(width: session.width, height: session.height, clientResized: session.clientResized))

        var format: CMFormatDescription?
        var needsKeyFrame = true
        var consecutiveDrops = 0
        var lastReset = Date.distantPast
        while true {
            header = try await stream.readExactly(12)
            if SessionHeader.isSession(header) {
                do { session = try SessionHeader.parse(header) } catch { throw MirrorError.protocolError("bad session packet: \(error)") }
                shared.videoSize = (session.width, session.height)
                needsKeyFrame = true
                events(.videoSize(width: session.width, height: session.height, clientResized: session.clientResized))
                continue
            }
            let packet: MediaPacketHeader
            do { packet = try MediaPacketHeader.parse(header) } catch { throw MirrorError.protocolError("bad packet header: \(error)") }
            let payload = try await stream.readExactly(packet.size)
            if packet.isConfig {
                do {
                    if codec == .av1 {
                        format = try VideoFormat.makeAV1(config: payload, width: session.width, height: session.height)
                    } else {
                        guard let sets = AnnexB.parameterSets(payload, codec: codec) else {
                            throw MirrorError.protocolError("config packet without parameter sets")
                        }
                        format = try VideoFormat.make(sets, codec: codec)
                    }
                } catch let e as MirrorError {
                    throw e
                } catch {
                    throw MirrorError.decoderFailed("format description: \(error)")
                }
                let dims = VideoFormat.dimensions(format!)
                sink.formatChanged(format!, width: dims.width, height: dims.height)
                needsKeyFrame = true
                continue
            }
            guard let format else { continue } // media before config: nothing to decode with yet
            if needsKeyFrame, !packet.isKeyFrame {
                consecutiveDrops += 1
                if consecutiveDrops >= 30, Date().timeIntervalSince(lastReset) > 1 {
                    control.send(.resetVideo)
                    lastReset = Date()
                    consecutiveDrops = 0
                }
                continue
            }
            consecutiveDrops = 0
            let sample: CMSampleBuffer
            do {
                let unit = codec == .av1 ? payload : AnnexB.toAVCC(payload)
                sample = try SampleBufferFactory.make(avcc: unit, format: format, ptsMicros: packet.pts, keyFrame: packet.isKeyFrame)
            } catch {
                throw MirrorError.decoderFailed("sample buffer: \(error)")
            }
            if sink.enqueue(sample, keyFrame: packet.isKeyFrame) {
                needsKeyFrame = false
            } else {
                // The sink dropped an inter frame: resync on a keyframe. Ask for one right away
                // (rate-limited like the drop path above) instead of waiting for the 10 s IDR interval.
                needsKeyFrame = true
                if Date().timeIntervalSince(lastReset) > 1 {
                    control.send(.resetVideo)
                    lastReset = Date()
                    consecutiveDrops = 0
                }
            }
            if sink.requiresFlush {
                sink.flush()
                needsKeyFrame = true
                control.send(.resetVideo)
            }
            if let failure = sink.failure { throw MirrorError.decoderFailed(failure) }
        }
    }

    private static func runAudio(
        _ stream: any ByteStream, sink: (any AudioSink)?, timeouts: Timeouts, events: @escaping @Sendable (MirrorEvent) -> Void
    ) async throws {
        let codecRaw = BigEndian.u32(try await withTimeout(timeouts.header, stage: .audioHeader) { try await stream.readExactly(4) }, at: 0)
        let codec = StreamCodecID(rawValue: codecRaw)
        switch codec {
        case .opus, .aac, .raw: break
        case .disabled:
            events(.audioUnavailable)
            // Keep the socket open (the server holds it) but nothing more arrives; just park until cancelled.
            while true { try await Task.sleep(nanoseconds: 1_000_000_000) }
        case .configError: throw MirrorError.audioConfigError
        default: throw MirrorError.unsupportedAudioCodec(codecRaw)
        }
        events(.audioCodec(codec))
        if codec == .raw { sink?.configure(codec: codec, config: nil) }
        while true {
            let header = try await stream.readExactly(12)
            let packet: MediaPacketHeader
            do { packet = try MediaPacketHeader.parse(header) } catch { throw MirrorError.protocolError("bad audio header: \(error)") }
            let payload = try await stream.readExactly(packet.size)
            if packet.isConfig {
                sink?.configure(codec: codec, config: payload)
            } else {
                sink?.enqueue(packet: payload)
            }
        }
    }

    private static func withTimeout<T: Sendable>(_ seconds: TimeInterval, stage: MirrorStage, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw MirrorError.handshakeTimeout(stage)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, stage: MirrorStage, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Self.withTimeout(seconds, stage: stage, body)
    }
}
