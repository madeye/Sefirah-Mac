import Foundation

public struct GeneralSettings: Codable, Sendable, Equatable {
    public var startupOption: StartupOptions
    public var theme: Theme
    public var scrcpyPath: String
    public var adbPath: String
    public var remoteStoragePath: String
    public var receivedFilesPath: String
    public var localDeviceName: String
    public var actions: [ActionItem]
    /// Native in-app mirror (default) or the bundled/external scrcpy binary.
    public var mirrorBackend: MirrorBackend
    /// Run scrcpy-server with `log_level=debug`.
    public var verboseMirrorLogs: Bool
    /// When the native mirror fails before streaming, open the external scrcpy window instead.
    public var mirrorFallbackToExternal: Bool

    public init(
        startupOption: StartupOptions = .inTray,
        theme: Theme = .default,
        scrcpyPath: String = "",
        adbPath: String = "",
        remoteStoragePath: String = SefirahConstants.defaultRemoteStorageDirectory.path,
        receivedFilesPath: String = SefirahConstants.defaultDownloadsDirectory.path,
        localDeviceName: String = "",
        actions: [ActionItem] = [],
        mirrorBackend: MirrorBackend = .native,
        verboseMirrorLogs: Bool = false,
        mirrorFallbackToExternal: Bool = false
    ) {
        self.startupOption = startupOption
        self.theme = theme
        self.scrcpyPath = scrcpyPath
        self.adbPath = adbPath
        self.remoteStoragePath = remoteStoragePath
        self.receivedFilesPath = receivedFilesPath
        self.localDeviceName = localDeviceName
        self.actions = actions
        self.mirrorBackend = mirrorBackend
        self.verboseMirrorLogs = verboseMirrorLogs
        self.mirrorFallbackToExternal = mirrorFallbackToExternal
    }

    /// Tolerant decoding so `general.json` files written before a field existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GeneralSettings()
        startupOption = try c.decodeIfPresent(StartupOptions.self, forKey: .startupOption) ?? defaults.startupOption
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? defaults.theme
        scrcpyPath = try c.decodeIfPresent(String.self, forKey: .scrcpyPath) ?? defaults.scrcpyPath
        adbPath = try c.decodeIfPresent(String.self, forKey: .adbPath) ?? defaults.adbPath
        remoteStoragePath = try c.decodeIfPresent(String.self, forKey: .remoteStoragePath) ?? defaults.remoteStoragePath
        receivedFilesPath = try c.decodeIfPresent(String.self, forKey: .receivedFilesPath) ?? defaults.receivedFilesPath
        localDeviceName = try c.decodeIfPresent(String.self, forKey: .localDeviceName) ?? defaults.localDeviceName
        actions = try c.decodeIfPresent([ActionItem].self, forKey: .actions) ?? defaults.actions
        mirrorBackend = try c.decodeIfPresent(MirrorBackend.self, forKey: .mirrorBackend) ?? defaults.mirrorBackend
        verboseMirrorLogs = try c.decodeIfPresent(Bool.self, forKey: .verboseMirrorLogs) ?? defaults.verboseMirrorLogs
        mirrorFallbackToExternal = try c.decodeIfPresent(Bool.self, forKey: .mirrorFallbackToExternal) ?? defaults.mirrorFallbackToExternal
    }
}

public enum MirrorBackend: String, Codable, Sendable, Equatable, CaseIterable {
    case native = "Native"
    case external = "External"
}
