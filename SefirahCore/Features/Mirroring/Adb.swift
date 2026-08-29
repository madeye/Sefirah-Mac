import Foundation

public struct AdbDevice: Equatable, Sendable {
    public var serial: String
    /// device | offline | unauthorized | …
    public var state: String
    /// "model:Pixel_7" from `devices -l`.
    public var model: String?
    public var isTcp: Bool { serial.contains(":") }

    public init(serial: String, state: String, model: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
    }
}

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult
}

public enum AdbError: Error, Equatable, LocalizedError {
    case spawnFailed(String)
    case timeout(command: String)
    case connectFailed(host: String, message: String)
    case noUsbDeviceForTcpip(model: String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let message):
            return "Could not start adb: \(message)"
        case .timeout(let command):
            return "adb timed out: \(command)"
        case .connectFailed(let host, let message):
            return "adb could not connect to \(host): \(message)"
        case .noUsbDeviceForTcpip(let model):
            return "No USB device matching \(model) is available to switch to TCP/IP mode."
        case .commandFailed(let command, let exitCode, let stderr):
            return "adb \(command) failed (exit \(exitCode))\(stderr.isEmpty ? "" : ": \(stderr)")"
        }
    }
}

/// Runs a short-lived command with Process + Pipes; kills it after `timeout`.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
        let box = OutputBox()
        out.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { fh.readabilityHandler = nil } else { box.appendOut(data) }
        }
        err.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { fh.readabilityHandler = nil } else { box.appendErr(data) }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeOnce()
            process.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                box.appendOut(out.fileHandleForReading.availableData)
                box.appendErr(err.fileHandleForReading.availableData)
                resumed.run { continuation.resume(returning: proc.terminationStatus) }
            }
            do {
                try process.run()
            } catch {
                resumed.run { continuation.resume(throwing: AdbError.spawnFailed(error.localizedDescription)) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                box.markTimedOut()
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        if box.timedOut { throw AdbError.timeout(command: command) }
        return CommandResult(exitCode: status, stdout: box.stdoutText, stderr: box.stderrText)
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        private var timedOutFlag = false
        func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
        func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
        func markTimedOut() { lock.lock(); timedOutFlag = true; lock.unlock() }
        var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOutFlag }
        var stdoutText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: out, as: UTF8.self) }
        var stderrText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: err, as: UTF8.self) }
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

/// Pure parsers for adb output.
public enum AdbOutput {
    public static func parseDevices(_ stdout: String) -> [AdbDevice] {
        var result: [AdbDevice] = []
        for rawLine in stdout.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices") || line.hasPrefix("*") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let model = parts.dropFirst(2).first { $0.hasPrefix("model:") }.map { String($0.dropFirst("model:".count)) }
            result.append(AdbDevice(serial: parts[0], state: parts[1], model: model))
        }
        return result
    }

    public static func connectSucceeded(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("connected to") && !text.contains("cannot connect") && !text.contains("failed to connect")
    }

    public static func modelMatches(adbModel: String?, peerModel: String) -> Bool {
        guard let adbModel else { return false }
        let a = normalize(adbModel), b = normalize(peerModel)
        return !a.isEmpty && a == b
    }

    static func normalize(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

public struct AdbClient: Sendable {
    public var adb: URL
    public var environment: [String: String]
    public var runner: any CommandRunning
    /// Delay between `tcpip` and the retried `connect` (legacy used 200 ms).
    public var tcpipSettleDelay: TimeInterval = 0.2

    public init(adb: URL, environment: [String: String], runner: any CommandRunning = ProcessCommandRunner()) {
        self.adb = adb
        self.environment = environment
        self.runner = runner
    }

    /// `adb devices -l`
    public func devices() async throws -> [AdbDevice] {
        let result = try await runner.run(adb, ["devices", "-l"], environment: environment, timeout: 5)
        guard result.exitCode == 0 else {
            throw AdbError.commandFailed(command: "devices -l", exitCode: result.exitCode, stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return AdbOutput.parseDevices(result.stdout)
    }

    /// `adb connect host:port` → serial
    public func connect(host: String, port: Int = 5555) async throws -> String {
        let target = "\(host):\(port)"
        let result = try await runner.run(adb, ["connect", target], environment: environment, timeout: 8)
        let combined = (result.stdout + "\n" + result.stderr)
        guard result.exitCode == 0, AdbOutput.connectSucceeded(combined) else {
            throw AdbError.connectFailed(host: target, message: combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return target
    }

    /// `adb -s serial tcpip port`
    public func tcpip(serial: String, port: Int = 5555) async throws {
        let result = try await runner.run(adb, ["-s", serial, "tcpip", String(port)], environment: environment, timeout: 5)
        guard result.exitCode == 0 else {
            throw AdbError.commandFailed(command: "-s \(serial) tcpip \(port)", exitCode: result.exitCode, stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Port of legacy TryConnectTcp: connect → else USB device with matching model → tcpip → sleep → connect.
    public func tryConnectTcp(host: String, model: String, port: Int = 5555) async throws -> String {
        do {
            return try await connect(host: host, port: port)
        } catch AdbError.connectFailed {
            // Fall through: try to switch a matching USB device to TCP/IP mode.
        }
        let devices = try await devices()
        guard let usb = devices.first(where: {
            $0.state == "device" && !$0.isTcp && AdbOutput.modelMatches(adbModel: $0.model, peerModel: model)
        }) else {
            throw AdbError.noUsbDeviceForTcpip(model: model)
        }
        try await tcpip(serial: usb.serial, port: port)
        try await Task.sleep(nanoseconds: UInt64(tcpipSettleDelay * 1_000_000_000))
        return try await connect(host: host, port: port)
    }
}

/// Pure port of the legacy DeviceSelection logic.
public enum ScrcpyDeviceSelection {
    /// nil = let scrcpy pick (exactly one device, or none visible — scrcpy reports that itself).
    public static func serial(devices: [AdbDevice], peerModel: String, preference: ScrcpyDevicePreferenceType) -> String? {
        let online = devices.filter { $0.state == "device" }
        guard online.count > 1 else { return nil }
        let matches = online.filter { AdbOutput.modelMatches(adbModel: $0.model, peerModel: peerModel) }
        guard !matches.isEmpty else { return nil }
        let usb = matches.first { !$0.isTcp }
        let tcp = matches.first { $0.isTcp }
        switch preference {
        case .usb: return usb?.serial ?? tcp?.serial
        case .tcpip: return tcp?.serial ?? usb?.serial
        case .auto, .askEverytime: return tcp?.serial ?? usb?.serial
        }
    }
}
