import Foundation

public struct DeviceSettings: Codable, Sendable, Equatable {
    public var deviceId: String

    public var clipboardReceive: Bool
    public var clipboardSend: Bool
    public var clipboardIncludeImages: Bool
    public var showClipboardToast: Bool
    public var openLinksInBrowser: Bool
    public var clipboardFiles: Bool

    public var notificationSync: Bool
    public var showNotificationToast: Bool
    public var showBadge: Bool
    public var notificationLaunchPreference: NotificationLaunchPreference
    public var ignoreHostApps: Bool
    public var ignoreNotificationDuringDnd: Bool

    public var lowBatteryAlertsEnabled: Bool
    public var lowBatteryAlertThreshold: Int
    public var lowBatteryAlertShown: Bool

    public var remoteStoragePath: String
    public var receivedFilesPath: String
    public var storageAccess: Bool

    public var scrcpyPath: String
    public var screenOff: Bool
    public var physicalKeyboard: Bool
    public var scrcpyClipboardAutosync: Bool
    public var unlockDeviceBeforeLaunch: Bool
    public var unlockTimeout: Int
    public var unlockCommands: [UnlockCommandEntry]
    public var videoBitrate: String
    public var videoResolution: String
    public var videoBuffer: Int
    public var audioBitrate: String
    public var audioBuffer: Int
    public var customArguments: String
    public var disableVideoForwarding: Bool
    public var videoCodec: Int
    public var frameRate: Int
    public var crop: String
    public var display: String
    public var virtualDisplaySize: String
    public var displayOrientation: Int
    public var rotationAngle: Int
    public var audioOutputMode: AudioOutputModeType
    public var forwardMicrophone: Bool
    public var audioOutputBuffer: Int
    public var audioCodec: Int
    public var scrcpyDevicePreference: ScrcpyDevicePreferenceType
    public var isVirtualDisplayEnabled: Bool
    public var flexDisplay: Bool
    /// Forward mouse hover (no button held) as `HOVER_MOVE` events.
    public var forwardHover: Bool

    public var adbPath: String
    public var autoConnect: Bool
    public var adbTcpipModeEnabled: Bool
    public var adbAutoConnect: Bool

    public var mediaSessionReceive: Bool
    /// No public macOS equivalent of GSMTC; kept for settings round-trip, no-op in v1.
    public var mediaSessionSend: Bool
    public var audioSync: Bool

    public init(deviceId: String) {
        self.deviceId = deviceId
        clipboardReceive = true
        clipboardSend = true
        clipboardIncludeImages = false
        showClipboardToast = false
        openLinksInBrowser = false
        clipboardFiles = false
        notificationSync = true
        showNotificationToast = true
        showBadge = true
        notificationLaunchPreference = .dynamic
        ignoreHostApps = true
        ignoreNotificationDuringDnd = true
        lowBatteryAlertsEnabled = true
        lowBatteryAlertThreshold = SefirahConstants.BatteryAlerts.defaultThreshold
        lowBatteryAlertShown = false
        remoteStoragePath = SefirahConstants.defaultRemoteStorageDirectory.path
        receivedFilesPath = SefirahConstants.defaultDownloadsDirectory.path
        storageAccess = true
        scrcpyPath = ""
        screenOff = true
        physicalKeyboard = false
        scrcpyClipboardAutosync = false
        unlockDeviceBeforeLaunch = false
        unlockTimeout = 0
        unlockCommands = []
        videoBitrate = ""
        videoResolution = ""
        videoBuffer = 0
        audioBitrate = ""
        audioBuffer = 0
        customArguments = ""
        disableVideoForwarding = false
        videoCodec = 0
        frameRate = 60
        crop = ""
        display = "0"
        virtualDisplaySize = ""
        displayOrientation = 0
        rotationAngle = 0
        audioOutputMode = .desktop
        forwardMicrophone = false
        audioOutputBuffer = 0
        audioCodec = 0
        scrcpyDevicePreference = .auto
        isVirtualDisplayEnabled = true
        flexDisplay = false
        forwardHover = false
        adbPath = ""
        autoConnect = true
        adbTcpipModeEnabled = false
        adbAutoConnect = true
        mediaSessionReceive = true
        mediaSessionSend = true
        audioSync = true
    }

    /// Tolerant decoding so device JSON files written before a field existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        var d = DeviceSettings(deviceId: deviceId)
        d.clipboardReceive = try c.decodeIfPresent(Bool.self, forKey: .clipboardReceive) ?? d.clipboardReceive
        d.clipboardSend = try c.decodeIfPresent(Bool.self, forKey: .clipboardSend) ?? d.clipboardSend
        d.clipboardIncludeImages = try c.decodeIfPresent(Bool.self, forKey: .clipboardIncludeImages) ?? d.clipboardIncludeImages
        d.showClipboardToast = try c.decodeIfPresent(Bool.self, forKey: .showClipboardToast) ?? d.showClipboardToast
        d.openLinksInBrowser = try c.decodeIfPresent(Bool.self, forKey: .openLinksInBrowser) ?? d.openLinksInBrowser
        d.clipboardFiles = try c.decodeIfPresent(Bool.self, forKey: .clipboardFiles) ?? d.clipboardFiles
        d.notificationSync = try c.decodeIfPresent(Bool.self, forKey: .notificationSync) ?? d.notificationSync
        d.showNotificationToast = try c.decodeIfPresent(Bool.self, forKey: .showNotificationToast) ?? d.showNotificationToast
        d.showBadge = try c.decodeIfPresent(Bool.self, forKey: .showBadge) ?? d.showBadge
        d.notificationLaunchPreference = try c.decodeIfPresent(NotificationLaunchPreference.self, forKey: .notificationLaunchPreference) ?? d.notificationLaunchPreference
        d.ignoreHostApps = try c.decodeIfPresent(Bool.self, forKey: .ignoreHostApps) ?? d.ignoreHostApps
        d.ignoreNotificationDuringDnd = try c.decodeIfPresent(Bool.self, forKey: .ignoreNotificationDuringDnd) ?? d.ignoreNotificationDuringDnd
        d.lowBatteryAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .lowBatteryAlertsEnabled) ?? d.lowBatteryAlertsEnabled
        d.lowBatteryAlertThreshold = try c.decodeIfPresent(Int.self, forKey: .lowBatteryAlertThreshold) ?? d.lowBatteryAlertThreshold
        d.lowBatteryAlertShown = try c.decodeIfPresent(Bool.self, forKey: .lowBatteryAlertShown) ?? d.lowBatteryAlertShown
        d.remoteStoragePath = try c.decodeIfPresent(String.self, forKey: .remoteStoragePath) ?? d.remoteStoragePath
        d.receivedFilesPath = try c.decodeIfPresent(String.self, forKey: .receivedFilesPath) ?? d.receivedFilesPath
        d.storageAccess = try c.decodeIfPresent(Bool.self, forKey: .storageAccess) ?? d.storageAccess
        d.scrcpyPath = try c.decodeIfPresent(String.self, forKey: .scrcpyPath) ?? d.scrcpyPath
        d.screenOff = try c.decodeIfPresent(Bool.self, forKey: .screenOff) ?? d.screenOff
        d.physicalKeyboard = try c.decodeIfPresent(Bool.self, forKey: .physicalKeyboard) ?? d.physicalKeyboard
        d.scrcpyClipboardAutosync = try c.decodeIfPresent(Bool.self, forKey: .scrcpyClipboardAutosync) ?? d.scrcpyClipboardAutosync
        d.unlockDeviceBeforeLaunch = try c.decodeIfPresent(Bool.self, forKey: .unlockDeviceBeforeLaunch) ?? d.unlockDeviceBeforeLaunch
        d.unlockTimeout = try c.decodeIfPresent(Int.self, forKey: .unlockTimeout) ?? d.unlockTimeout
        d.unlockCommands = try c.decodeIfPresent([UnlockCommandEntry].self, forKey: .unlockCommands) ?? d.unlockCommands
        d.videoBitrate = try c.decodeIfPresent(String.self, forKey: .videoBitrate) ?? d.videoBitrate
        d.videoResolution = try c.decodeIfPresent(String.self, forKey: .videoResolution) ?? d.videoResolution
        d.videoBuffer = try c.decodeIfPresent(Int.self, forKey: .videoBuffer) ?? d.videoBuffer
        d.audioBitrate = try c.decodeIfPresent(String.self, forKey: .audioBitrate) ?? d.audioBitrate
        d.audioBuffer = try c.decodeIfPresent(Int.self, forKey: .audioBuffer) ?? d.audioBuffer
        d.customArguments = try c.decodeIfPresent(String.self, forKey: .customArguments) ?? d.customArguments
        d.disableVideoForwarding = try c.decodeIfPresent(Bool.self, forKey: .disableVideoForwarding) ?? d.disableVideoForwarding
        d.videoCodec = try c.decodeIfPresent(Int.self, forKey: .videoCodec) ?? d.videoCodec
        d.frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? d.frameRate
        d.crop = try c.decodeIfPresent(String.self, forKey: .crop) ?? d.crop
        d.display = try c.decodeIfPresent(String.self, forKey: .display) ?? d.display
        d.virtualDisplaySize = try c.decodeIfPresent(String.self, forKey: .virtualDisplaySize) ?? d.virtualDisplaySize
        d.displayOrientation = try c.decodeIfPresent(Int.self, forKey: .displayOrientation) ?? d.displayOrientation
        d.rotationAngle = try c.decodeIfPresent(Int.self, forKey: .rotationAngle) ?? d.rotationAngle
        d.audioOutputMode = try c.decodeIfPresent(AudioOutputModeType.self, forKey: .audioOutputMode) ?? d.audioOutputMode
        d.forwardMicrophone = try c.decodeIfPresent(Bool.self, forKey: .forwardMicrophone) ?? d.forwardMicrophone
        d.audioOutputBuffer = try c.decodeIfPresent(Int.self, forKey: .audioOutputBuffer) ?? d.audioOutputBuffer
        d.audioCodec = try c.decodeIfPresent(Int.self, forKey: .audioCodec) ?? d.audioCodec
        d.scrcpyDevicePreference = try c.decodeIfPresent(ScrcpyDevicePreferenceType.self, forKey: .scrcpyDevicePreference) ?? d.scrcpyDevicePreference
        d.isVirtualDisplayEnabled = try c.decodeIfPresent(Bool.self, forKey: .isVirtualDisplayEnabled) ?? d.isVirtualDisplayEnabled
        d.flexDisplay = try c.decodeIfPresent(Bool.self, forKey: .flexDisplay) ?? d.flexDisplay
        d.forwardHover = try c.decodeIfPresent(Bool.self, forKey: .forwardHover) ?? d.forwardHover
        d.adbPath = try c.decodeIfPresent(String.self, forKey: .adbPath) ?? d.adbPath
        d.autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? d.autoConnect
        d.adbTcpipModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .adbTcpipModeEnabled) ?? d.adbTcpipModeEnabled
        d.adbAutoConnect = try c.decodeIfPresent(Bool.self, forKey: .adbAutoConnect) ?? d.adbAutoConnect
        d.mediaSessionReceive = try c.decodeIfPresent(Bool.self, forKey: .mediaSessionReceive) ?? d.mediaSessionReceive
        d.mediaSessionSend = try c.decodeIfPresent(Bool.self, forKey: .mediaSessionSend) ?? d.mediaSessionSend
        d.audioSync = try c.decodeIfPresent(Bool.self, forKey: .audioSync) ?? d.audioSync
        self = d
    }

    public mutating func clampBatteryThreshold() {
        lowBatteryAlertThreshold = min(
            SefirahConstants.BatteryAlerts.maxThreshold,
            max(SefirahConstants.BatteryAlerts.minThreshold, lowBatteryAlertThreshold)
        )
    }
}
