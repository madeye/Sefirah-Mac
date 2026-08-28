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

    public init(
        startupOption: StartupOptions = .inTray,
        theme: Theme = .default,
        scrcpyPath: String = "",
        adbPath: String = "",
        remoteStoragePath: String = SefirahConstants.defaultRemoteStorageDirectory.path,
        receivedFilesPath: String = SefirahConstants.defaultDownloadsDirectory.path,
        localDeviceName: String = "",
        actions: [ActionItem] = []
    ) {
        self.startupOption = startupOption
        self.theme = theme
        self.scrcpyPath = scrcpyPath
        self.adbPath = adbPath
        self.remoteStoragePath = remoteStoragePath
        self.receivedFilesPath = receivedFilesPath
        self.localDeviceName = localDeviceName
        self.actions = actions
    }
}
