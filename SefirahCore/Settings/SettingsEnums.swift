import Foundation

public enum Theme: String, Codable, Sendable, Equatable {
    case `default` = "Default"
    case light = "Light"
    case dark = "Dark"
}

public enum StartupOptions: String, Codable, Sendable, Equatable {
    case disabled = "Disabled"
    case minimized = "Minimized"
    case inTray = "InTray"
    case maximized = "Maximized"
}

public enum NotificationFilter: Int, Codable, Sendable, Equatable {
    case disabled = 0
    case feed = 1
    case toastFeed = 2
}

public enum NotificationLaunchPreference: Int, Codable, Sendable, Equatable {
    case nothing = 0
    case openInRemoteDevice = 1
    case dynamic = 2
}

public enum AudioOutputModeType: String, Codable, Sendable, Equatable {
    case desktop = "Desktop"
    case remote = "Remote"
    case both = "Both"
}

public enum ScrcpyDevicePreferenceType: String, Codable, Sendable, Equatable {
    case auto = "Auto"
    case usb = "Usb"
    case tcpip = "Tcpip"
    case askEverytime = "AskEverytime"
}

public struct UnlockCommandEntry: Codable, Sendable, Equatable {
    public var command: String
    public var delayMs: Int

    public init(command: String, delayMs: Int = 0) {
        self.command = command
        self.delayMs = delayMs
    }
}

public struct ActionItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var icon: String?
    public var askForConfirmation: Bool
    public var actionId: String
    public var settings: [String: String]

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        icon: String? = nil,
        askForConfirmation: Bool = false,
        actionId: String,
        settings: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.askForConfirmation = askForConfirmation
        self.actionId = actionId
        self.settings = settings
    }
}
