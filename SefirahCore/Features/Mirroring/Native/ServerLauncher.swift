import Foundation

/// The `adb shell app_process … Server` process on the Mac side.
public protocol ServerProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    /// Non-nil once the process exited.
    var exitStatus: Int32? { get }
    /// Last 16 KiB of `[server] …` output.
    var logTail: String { get }
    func terminate()
    /// Exit status, or nil if still running after `timeout`.
    func waitForExit(timeout: TimeInterval) async -> Int32?
}

public protocol DetachedProcessSpawning: Sendable {
    func spawn(_ executable: URL, _ arguments: [String], environment: [String: String],
               onLine: @escaping @Sendable (String) -> Void) throws -> any ServerProcess
}

/// `Process` + pipes, line-split stdout/stderr, bounded tail.
public final class ProcessServerProcess: ServerProcess, @unchecked Sendable {
    public static let tailBytes = 16 * 1024

    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let lock = NSLock()
    private var tail = Data()
    private var status: Int32?
    private var partial: [ObjectIdentifier: Data] = [:]
    private let onLine: @Sendable (String) -> Void

    fileprivate init(executable: URL, arguments: [String], environment: [String: String], onLine: @escaping @Sendable (String) -> Void) throws {
        self.onLine = onLine
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        for handle in [stdout.fileHandleForReading, stderr.fileHandleForReading] {
            handle.readabilityHandler = { [weak self] fh in
                let data = fh.availableData
                if data.isEmpty { fh.readabilityHandler = nil } else { self?.consume(data, from: fh) }
            }
        }
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            for handle in [self.stdout.fileHandleForReading, self.stderr.fileHandleForReading] {
                handle.readabilityHandler = nil
                let rest = handle.availableData
                if !rest.isEmpty { self.consume(rest, from: handle) }
                self.flushPartial(handle)
                try? handle.close()
            }
            self.lock.lock()
            self.status = proc.terminationReason == .uncaughtSignal ? -proc.terminationStatus : proc.terminationStatus
            self.lock.unlock()
        }
        try process.run()
    }

    private func consume(_ data: Data, from handle: FileHandle) {
        var lines: [String] = []
        lock.lock()
        tail.append(data)
        if tail.count > Self.tailBytes { tail.removeFirst(tail.count - Self.tailBytes) }
        var buffer = partial[ObjectIdentifier(handle)] ?? Data()
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0a) {
            lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self).trimmingCharacters(in: .init(charactersIn: "\r")))
            buffer = Data(buffer[(nl + 1)...])
        }
        partial[ObjectIdentifier(handle)] = buffer
        lock.unlock()
        lines.forEach(onLine)
    }

    private func flushPartial(_ handle: FileHandle) {
        lock.lock()
        let rest = partial.removeValue(forKey: ObjectIdentifier(handle)) ?? Data()
        lock.unlock()
        if !rest.isEmpty { onLine(String(decoding: rest, as: UTF8.self)) }
    }

    public var isRunning: Bool { process.isRunning }

    public var exitStatus: Int32? { lock.lock(); defer { lock.unlock() }; return status }

    public var logTail: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    public func waitForExit(timeout: TimeInterval) async -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = exitStatus { return status }
            if !process.isRunning, let status = exitStatus { return status }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return exitStatus
    }
}

public struct ProcessDetachedSpawner: DetachedProcessSpawning {
    public init() {}
    public func spawn(_ executable: URL, _ arguments: [String], environment: [String: String],
                      onLine: @escaping @Sendable (String) -> Void) throws -> any ServerProcess
    {
        try ProcessServerProcess(executable: executable, arguments: arguments, environment: environment, onLine: onLine)
    }
}

/// Push / tunnel / spawn / kill for the device-side scrcpy server.
public struct ServerLauncher: Sendable {
    public var adb: AdbClient
    public var serverJar: URL
    public var spawner: any DetachedProcessSpawning

    public init(adb: AdbClient, serverJar: URL, spawner: any DetachedProcessSpawning = ProcessDetachedSpawner()) {
        self.adb = adb
        self.serverJar = serverJar
        self.spawner = spawner
    }

    public func push(serial: String) async throws {
        try await adb.push(serial: serial, local: serverJar, remote: ServerOptions.remoteJarPath)
    }

    public func forward(serial: String, socketName: String) async throws -> UInt16 {
        try await adb.forward(serial: serial, socketName: socketName)
    }

    public func removeForward(serial: String, port: UInt16) async {
        _ = try? await adb.forwardRemove(serial: serial, port: port)
    }

    public static func spawnArguments(serial: String, options: ServerOptions) throws -> [String] {
        ["-s", serial, "shell", "CLASSPATH=\(ServerOptions.remoteJarPath)", "app_process", "/", ServerOptions.serverClass]
            + (try options.arguments())
    }

    public func spawn(serial: String, options: ServerOptions, onLine: @escaping @Sendable (String) -> Void) throws -> any ServerProcess {
        try spawner.spawn(adb.adb, try Self.spawnArguments(serial: serial, options: options), environment: adb.environment, onLine: onLine)
    }

    /// `adb -s serial shell <command>` (one shell string; the device shell parses it).
    public func shell(serial: String, _ command: String, timeout: TimeInterval) async throws -> CommandResult {
        try await adb.shell(serial: serial, [command], timeout: timeout)
    }

    /// Best-effort kill of *this session's* server only: `pkill -f "scid=<%08x>"`. The scid token is on the
    /// server's cmdline but not on other sessions' servers, an external scrcpy's server, or the detached
    /// `CleanUp` process (which restores display power / stay-awake after the server exits).
    public func killServer(serial: String, scid: UInt32) async {
        _ = try? await adb.shell(serial: serial, ["pkill", "-f", Self.killPattern(scid: scid)], timeout: 3)
    }

    public static func killPattern(scid: UInt32) -> String {
        String(format: "scid=%08x", scid & 0x7fff_ffff)
    }
}
