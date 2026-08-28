import Foundation

/// Wire enums. Members with a `String` raw value use
/// `JsonStringEnumConverter` on the C# side (PascalCase names).
/// `AudioStreamType` is a numeric C# enum and MUST stay an integer on the wire.

public enum PlaybackInfoType: String, Codable, Sendable, Equatable {
    case playbackInfo = "PlaybackInfo"
    case playbackUpdate = "PlaybackUpdate"
    case timelineUpdate = "TimelineUpdate"
    case removedSession = "RemovedSession"
}

public enum MediaActionType: String, Codable, Sendable, Equatable {
    case play = "Play"
    case pause = "Pause"
    case stop = "Stop"
    case next = "Next"
    case previous = "Previous"
    case seek = "Seek"
    case shuffle = "Shuffle"
    case `repeat` = "Repeat"
    case playbackRate = "PlaybackRate"
    case volumeUpdate = "VolumeUpdate"
}

public enum AudioActionType: String, Codable, Sendable, Equatable {
    case defaultDevice = "DefaultDevice"
    case volumeUpdate = "VolumeUpdate"
    case toggleMute = "ToggleMute"
}

public enum AudioInfoType: String, Codable, Sendable, Equatable {
    case new = "New"
    case removed = "Removed"
    case active = "Active"
}

public enum NotificationInfoType: String, Codable, Sendable, Equatable {
    case active = "Active"
    case removed = "Removed"
    case new = "New"
    case invoke = "Invoke"
}

public enum ConversationInfoType: String, Codable, Sendable, Equatable {
    case active = "Active"
    case activeUpdated = "ActiveUpdated"
    case removed = "Removed"
    case new = "New"
}

public enum CallState: String, Codable, Sendable, Equatable {
    case ringing = "Ringing"
    case inProgress = "InProgress"
    case missedCall = "MissedCall"
}

public enum CallLogType: String, Codable, Sendable, Equatable {
    case incoming = "Incoming"
    case outgoing = "Outgoing"
    case missed = "Missed"
    case voicemail = "Voicemail"
    case rejected = "Rejected"
    case blocked = "Blocked"
    case answeredExternally = "AnsweredExternally"
    case unknown = "Unknown"
}

/// Android AudioManager stream type constants. Serialized as integers.
public enum AudioStreamType: Int, Codable, Sendable, Equatable, Hashable {
    case voiceCall = 0
    case ring = 2
    case media = 3
    case alarm = 4
    case notification = 5
}
