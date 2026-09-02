import Foundation

public enum MirrorStage: Equatable, Sendable {
    case unlock, push, tunnel, spawn, dummyByte, deviceMeta, videoHeader, audioHeader

    public var description: String {
        switch self {
        case .unlock: return "Unlocking phone…"
        case .push: return "Pushing server…"
        case .tunnel: return "Opening tunnel…"
        case .spawn: return "Starting server…"
        case .dummyByte, .deviceMeta, .videoHeader, .audioHeader: return "Connecting…"
        }
    }
}

public enum MirrorError: Error, Equatable, Sendable {
    case toolsMissing
    case adb(AdbError)
    case noDevice
    case invalidOptions(String)
    case serverSpawnFailed(String)
    case serverExited(code: Int32, log: String)
    case versionMismatch(String)
    case handshakeTimeout(MirrorStage)
    case protocolError(String)
    case unsupportedVideoCodec(UInt32)
    case unsupportedAudioCodec(UInt32)
    case videoConfigError
    case audioConfigError
    case decoderFailed(String)
    case connectionLost
    case cancelled

    public var title: String {
        switch self {
        case .toolsMissing: return "Bundled adb / scrcpy-server missing"
        case .adb(let e): return e.errorDescription ?? "adb failed"
        case .noDevice: return "No ADB device found"
        case .invalidOptions(let s): return "Invalid mirror settings: \(s)"
        case .serverSpawnFailed(let s): return "Could not start adb: \(s)"
        case .serverExited(let code, _): return "scrcpy-server exited (code \(code))"
        case .versionMismatch(let s): return "scrcpy-server version mismatch: \(s)"
        case .handshakeTimeout(let stage): return "Timed out (\(stage.description.trimmingCharacters(in: .init(charactersIn: "…"))))"
        case .protocolError(let s): return "Protocol error: \(s)"
        case .unsupportedVideoCodec(let id): return "Unsupported video codec \(StreamCodecID(rawValue: id).displayName)"
        case .unsupportedAudioCodec(let id): return "Unsupported audio codec \(StreamCodecID(rawValue: id).displayName)"
        case .videoConfigError: return "The phone could not start its video encoder"
        case .audioConfigError: return "The phone could not start its audio encoder"
        case .decoderFailed(let s): return "Video decoder failed: \(s)"
        case .connectionLost: return "Device disconnected"
        case .cancelled: return "Cancelled"
        }
    }
}

public enum MirrorState: Equatable, Sendable {
    case idle
    case preparing(MirrorStage)
    case connecting
    case streaming
    case stopping
    case failed(MirrorError)

    public var isActive: Bool {
        switch self {
        case .idle, .failed: return false
        default: return true
        }
    }
}

public enum MirrorEvent: Sendable {
    case state(MirrorState)
    case deviceName(String)
    case videoCodec(StreamCodecID)
    case audioCodec(StreamCodecID)
    case videoSize(width: Int, height: Int, clientResized: Bool)
    case audioUnavailable
    case clipboard(String)
    case clipboardAck(UInt64)
    case uhidOutput(id: UInt16, data: Data)
    case serverLog(String)
    case warning(String)
}

public struct MirrorSessionConfig: Sendable, Equatable {
    public var key: String
    public var serial: String
    public var options: ServerOptions
    public var actions: [StartupAction]
    /// `DeviceSettings.audioBuffer` (ms; 0 → 50).
    public var audioTargetLatencyMs: Int
    /// `adb shell` commands run before the server is pushed (`DeviceSettings.unlockCommands` when enabled).
    public var unlockCommands: [UnlockCommandEntry]
    /// Per-command timeout in seconds.
    public var unlockTimeout: TimeInterval

    public init(key: String, serial: String, options: ServerOptions, actions: [StartupAction] = [], audioTargetLatencyMs: Int = 50,
                unlockCommands: [UnlockCommandEntry] = [], unlockTimeout: TimeInterval = 5)
    {
        self.key = key
        self.serial = serial
        self.options = options
        self.actions = actions
        self.audioTargetLatencyMs = audioTargetLatencyMs
        self.unlockCommands = unlockCommands
        self.unlockTimeout = unlockTimeout
    }
}
