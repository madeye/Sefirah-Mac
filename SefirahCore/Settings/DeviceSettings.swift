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
        adbPath = ""
        autoConnect = true
        adbTcpipModeEnabled = false
        adbAutoConnect = true
        mediaSessionReceive = true
        mediaSessionSend = true
        audioSync = true
    }

    public mutating func clampBatteryThreshold() {
        lowBatteryAlertThreshold = min(
            SefirahConstants.BatteryAlerts.maxThreshold,
            max(SefirahConstants.BatteryAlerts.minThreshold, lowBatteryAlertThreshold)
        )
    }
}
