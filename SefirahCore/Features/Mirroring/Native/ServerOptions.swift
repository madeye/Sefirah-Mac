import Foundation

public enum ServerOptionsError: Error, Equatable, Sendable, LocalizedError {
    case invalidValue(key: String, value: String)
    case invalidBitrate(String)
    case invalidCrop(String)
    case invalidDisplayId(String)
    case cropWithFlexDisplay
    case unsupportedCodec(String)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let key, let value): return "Invalid value for \(key): \"\(value)\""
        case .invalidBitrate(let s): return "Invalid bitrate \"\(s)\" (use e.g. 8M, 2000K or 500000)"
        case .invalidCrop(let s): return "Invalid crop \"\(s)\" (expected width:height:x:y)"
        case .invalidDisplayId(let s): return "Invalid display id \"\(s)\""
        case .cropWithFlexDisplay: return "Crop cannot be combined with a flexible virtual display"
        case .unsupportedCodec(let s): return "Video codec \(s) is not supported on this Mac"
        }
    }
}

/// Options for `com.genymobile.scrcpy.Server` (scrcpy 4.1 `key=value` arguments).
public struct ServerOptions: Sendable, Equatable {
    /// Must equal `SCRCPY_VERSION` in scripts/scrcpy.lock (pinned by a unit test).
    public static let serverVersion = "4.1"
    public static let remoteJarPath = "/data/local/tmp/scrcpy-server.jar"
    public static let serverClass = "com.genymobile.scrcpy.Server"

    public enum VideoCodec: String, Sendable, CaseIterable { case h264, h265, av1 }
    public enum AudioCodec: String, Sendable, CaseIterable { case opus, aac, raw }
    public enum AudioSource: String, Sendable, CaseIterable { case output, mic, playback }

    public var scid: UInt32
    public var logLevel = "info"
    public var video = true
    public var audio = true
    public var control = true
    public var videoCodec: VideoCodec = .h264
    public var audioCodec: AudioCodec = .opus
    public var audioSource: AudioSource = .output
    public var audioDup = false
    public var maxSize = 0
    public var videoBitRate = 8_000_000
    public var audioBitRate = 128_000
    public var maxFps = 0
    public var angle = 0
    public var crop: String?
    public var displayId = 0
    public var newDisplay: String?
    public var flexDisplay = false
    public var keepActive = false
    public var clipboardAutosync = true
    /// From `customArguments`, validated; emitted sorted by key.
    public var extra: [String: String] = [:]

    public init(scid: UInt32) {
        self.scid = scid & 0x7fff_ffff
    }

    public var socketName: String { String(format: "scrcpy_%08x", scid) }

    /// Characters that would be interpreted by the device shell (`app/src/server.c`).
    static let forbiddenCharacters: Set<Unicode.Scalar> = Set(" ;'\"*$?&`#\\|<>[]{}()!~".unicodeScalars).union(["\r", "\n"])

    public static func validate(_ value: String, key: String) throws {
        if value.unicodeScalars.contains(where: { forbiddenCharacters.contains($0) }) || value.isEmpty && key != "new_display" {
            throw ServerOptionsError.invalidValue(key: key, value: value)
        }
    }

    /// `["4.1", "scid=…", "log_level=…", "tunnel_forward=true", <non-defaults>, <extra sorted>]`
    public func arguments() throws -> [String] {
        var args = [Self.serverVersion, "scid=\(String(format: "%08x", scid))", "log_level=\(logLevel)", "tunnel_forward=true"]
        func add(_ key: String, _ value: String) throws {
            try Self.validate(value, key: key)
            args.append("\(key)=\(value)")
        }
        if !video { try add("video", "false") }
        if !audio { try add("audio", "false") }
        if !control { try add("control", "false") }
        if videoCodec != .h264 { try add("video_codec", videoCodec.rawValue) }
        if audioCodec != .opus { try add("audio_codec", audioCodec.rawValue) }
        if audioSource != .output { try add("audio_source", audioSource.rawValue) }
        if audioDup { try add("audio_dup", "true") }
        if maxSize > 0 { try add("max_size", String(maxSize)) }
        if videoBitRate != 8_000_000 { try add("video_bit_rate", String(videoBitRate)) }
        if audioBitRate != 128_000 { try add("audio_bit_rate", String(audioBitRate)) }
        if maxFps > 0 { try add("max_fps", String(maxFps)) }
        if angle != 0 { try add("angle", String(angle)) }
        if let crop { try add("crop", crop) }
        if displayId != 0 { try add("display_id", String(displayId)) }
        if let newDisplay { try add("new_display", newDisplay) }
        if flexDisplay { try add("flex_display", "true") }
        if keepActive { try add("keep_active", "true") }
        if !clipboardAutosync { try add("clipboard_autosync", "false") }
        for key in extra.keys.sorted() {
            try Self.validate(key, key: key)
            try add(key, extra[key]!)
        }
        return args
    }
}

/// Sent over the control socket right after the handshake, in order.
public enum StartupAction: Equatable, Sendable {
    case displayPower(on: Bool)
    case uhidKeyboard
    case startApp(String)
}

public enum ServerOptionsBuilder {
    public struct Result: Sendable, Equatable {
        public var options: ServerOptions
        /// Non-fatal notes (e.g. ignored scrcpy CLI flags in custom arguments).
        public var warnings: [String]
    }

    public static func build(settings: DeviceSettings, package: String?, scid: UInt32, av1Supported: Bool, verboseLogs: Bool = false) throws -> Result {
        var o = ServerOptions(scid: scid)
        var warnings: [String] = []
        o.logLevel = verboseLogs ? "debug" : "info"

        let virtualDisplay = package != nil && settings.isVirtualDisplayEnabled
        let flex = virtualDisplay && settings.flexDisplay

        if let size = nonempty(settings.videoResolution) {
            guard let n = Int(size), n >= 0 else { throw ServerOptionsError.invalidValue(key: "max_size", value: size) }
            o.maxSize = n
        }
        let bitrate = (package != nil && flex) ? "16M" : settings.videoBitrate
        if let b = nonempty(bitrate) {
            guard let bps = parseBitrate(b) else { throw ServerOptionsError.invalidBitrate(b) }
            o.videoBitRate = bps
        }
        if settings.frameRate > 0 { o.maxFps = settings.frameRate }
        if let crop = nonempty(settings.crop) {
            guard isCrop(crop) else { throw ServerOptionsError.invalidCrop(crop) }
            if flex { throw ServerOptionsError.cropWithFlexDisplay }
            o.crop = crop
        }
        if let display = nonempty(settings.display), display != "0", !virtualDisplay {
            guard let id = Int(display), id >= 0 else { throw ServerOptionsError.invalidDisplayId(display) }
            o.displayId = id
        }
        switch settings.videoCodec {
        case 1: o.videoCodec = .h265
        case 2:
            guard av1Supported else { throw ServerOptionsError.unsupportedCodec("AV1") }
            o.videoCodec = .av1
        default: o.videoCodec = .h264
        }
        if settings.disableVideoForwarding { o.video = false }
        switch settings.audioOutputMode {
        case .remote: o.audio = false
        case .both:
            o.audioSource = .playback
            o.audioDup = true
        case .desktop: break
        }
        if settings.forwardMicrophone { o.audioSource = .mic; o.audioDup = false }
        if let ab = nonempty(settings.audioBitrate) {
            guard let bps = parseBitrate(ab) else { throw ServerOptionsError.invalidBitrate(ab) }
            o.audioBitRate = bps
        }
        switch settings.audioCodec {
        case 1: o.audioCodec = .aac
        case 2: o.audioCodec = .raw
        default: o.audioCodec = .opus
        }
        o.clipboardAutosync = settings.scrcpyClipboardAutosync
        if virtualDisplay {
            o.newDisplay = nonempty(settings.virtualDisplaySize) ?? ""
            o.displayId = 0
            if flex {
                o.flexDisplay = true
                o.keepActive = true
            }
        }
        if settings.rotationAngle != 0 { o.angle = settings.rotationAngle }
        for token in settings.customArguments.split(whereSeparator: \.isWhitespace).map(String.init) {
            if token.hasPrefix("-") {
                warnings.append("Ignored scrcpy CLI flag \"\(token)\" (native mirror takes key=value server options)")
                continue
            }
            guard let eq = token.firstIndex(of: "="), eq != token.startIndex else {
                warnings.append("Ignored custom argument \"\(token)\" (expected key=value)")
                continue
            }
            let key = String(token[..<eq]), value = String(token[token.index(after: eq)...])
            try ServerOptions.validate(value, key: key)
            o.extra[key] = value
        }
        _ = try o.arguments()
        return Result(options: o, warnings: warnings)
    }

    /// Order: display power, UHID keyboard, start app.
    public static func startupActions(settings: DeviceSettings, package: String?) -> [StartupAction] {
        var actions: [StartupAction] = []
        if settings.screenOff { actions.append(.displayPower(on: false)) }
        if settings.physicalKeyboard { actions.append(.uhidKeyboard) }
        if let package = package.flatMap(nonempty) { actions.append(.startApp(package)) }
        return actions
    }

    /// "8M" → 8_000_000, "2000K" → 2_000_000, "500000" → 500000 (case-insensitive).
    public static func parseBitrate(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        guard !t.isEmpty else { return nil }
        var multiplier = 1
        var digits = Substring(t)
        if t.hasSuffix("M") { multiplier = 1_000_000; digits = t.dropLast() }
        else if t.hasSuffix("K") { multiplier = 1_000; digits = t.dropLast() }
        guard let n = Int(digits), n > 0 else { return nil }
        return n * multiplier
    }

    static func isCrop(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
