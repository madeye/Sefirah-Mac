import Foundation

public enum ScrcpyExit: Equatable, Sendable {
    /// 0 = success, 2 = SCRCPY_EXIT_DISCONNECTED (device unplugged).
    case normal(code: Int32)
    /// Anything else.
    case failure(code: Int32, stderr: String)
    /// SIGKILL (9) typically = code-signature rejection.
    case signaled(Int32, stderr: String)

    public static let okCodes: Set<Int32> = [0, 2]
}

public protocol ScrcpyRunning: AnyObject, Sendable {
    /// Launches; if a process for `key` is already running it is terminated first.
    func launch(_ plan: ScrcpyLaunchPlan, key: String, onExit: @escaping @Sendable (ScrcpyExit) -> Void) throws
    func terminate(key: String)
    func terminateAll()
    var runningKeys: Set<String> { get }
}

/// Spawns a long-lived scrcpy process per key, drains stderr into a bounded tail buffer,
/// and reports the exit on an arbitrary thread.
public final class ScrcpyProcessRunner: ScrcpyRunning, @unchecked Sendable {
    public static let stderrTailBytes = 16 * 1024

    private final class Entry: @unchecked Sendable {
        let process = Process()
        let pipe = Pipe()
        let lock = NSLock()
        var tail = Data()

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            tail.append(data)
            if tail.count > ScrcpyProcessRunner.stderrTailBytes {
                tail.removeFirst(tail.count - ScrcpyProcessRunner.stderrTailBytes)
            }
        }

        var stderrText: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    public var runningKeys: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(entries.keys)
    }

    public func launch(_ plan: ScrcpyLaunchPlan, key: String, onExit: @escaping @Sendable (ScrcpyExit) -> Void) throws {
        terminate(key: key)

        let entry = Entry()
        let process = entry.process
        process.executableURL = plan.executable
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = entry.pipe

        let handle = entry.pipe.fileHandleForReading
        handle.readabilityHandler = { [entry] fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
            } else {
                entry.append(data)
            }
        }

        process.terminationHandler = { [weak self, entry] proc in
            handle.readabilityHandler = nil
            entry.append(handle.availableData)
            try? handle.close()
            if let self {
                self.lock.lock()
                if self.entries[key] === entry { self.entries.removeValue(forKey: key) }
                self.lock.unlock()
            }
            let stderr = entry.stderrText
            let exit: ScrcpyExit
            switch proc.terminationReason {
            case .uncaughtSignal:
                exit = .signaled(proc.terminationStatus, stderr: stderr)
            default:
                exit = ScrcpyExit.okCodes.contains(proc.terminationStatus)
                    ? .normal(code: proc.terminationStatus)
                    : .failure(code: proc.terminationStatus, stderr: stderr)
            }
            onExit(exit)
        }

        lock.lock()
        entries[key] = entry
        lock.unlock()
        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            lock.lock()
            if entries[key] === entry { entries.removeValue(forKey: key) }
            lock.unlock()
            throw error
        }
    }

    public func terminate(key: String) {
        lock.lock()
        let entry = entries[key]
        lock.unlock()
        guard let entry, entry.process.isRunning else { return }
        entry.process.terminate()
    }

    public func terminateAll() {
        lock.lock()
        let all = Array(entries.values)
        lock.unlock()
        for entry in all where entry.process.isRunning {
            entry.process.terminate()
        }
    }
}
