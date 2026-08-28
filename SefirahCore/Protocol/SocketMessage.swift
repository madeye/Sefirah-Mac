import Foundation

/// Discriminator values are the C# class names (`nameof(T)`), PascalCase.
/// Property names on the wire are camelCase.
public enum SocketMessage: Sendable, Equatable {
    case actionInfo(ActionInfo)
    case actionList(ActionList)
    case applicationInfo(ApplicationInfo)
    case applicationList(ApplicationList)
    case authentication(Authentication)
    case audioAction(AudioAction)
    case audioDeviceInfo(AudioDeviceInfo)
    case audioStreamState(AudioStreamState)
    case batteryState(BatteryState)
    case bluetoothPairingRequest
    case bluetoothPairingResult(BluetoothPairingResult)
    case callInfo(CallInfo)
    case callLogInfo(CallLogInfo)
    case clearNotifications
    case clipboardInfo(ClipboardInfo)
    case contactInfo(ContactInfo)
    case conversationInfo(ConversationInfo)
    case deviceInfo(DeviceInfo)
    case disconnect
    case dndState(DndState)
    case fileTransferInfo(FileTransferInfo)
    case mediaAction(MediaAction)
    case notificationAction(NotificationAction)
    case notificationInfo(NotificationInfo)
    case notificationReply(NotificationReply)
    case pairMessage(PairMessage)
    case playbackInfo(PlaybackInfo)
    case playSound(PlaySound)
    case requestApplicationList
    case requestWorkerLaunch(RequestWorkerLaunch)
    case ringerModeState(RingerModeState)
    case sftpServerInfo(SftpServerInfo)
    case textMessage(TextMessage)
    case threadRequest(ThreadRequest)
    case udpBroadcast(UdpBroadcast)

    /// PascalCase `type` discriminator, matching `[JsonDerivedType(typeof(T), nameof(T))]`.
    public var typeName: String {
        switch self {
        case .actionInfo: "ActionInfo"
        case .actionList: "ActionList"
        case .applicationInfo: "ApplicationInfo"
        case .applicationList: "ApplicationList"
        case .authentication: "Authentication"
        case .audioAction: "AudioAction"
        case .audioDeviceInfo: "AudioDeviceInfo"
        case .audioStreamState: "AudioStreamState"
        case .batteryState: "BatteryState"
        case .bluetoothPairingRequest: "BluetoothPairingRequest"
        case .bluetoothPairingResult: "BluetoothPairingResult"
        case .callInfo: "CallInfo"
        case .callLogInfo: "CallLogInfo"
        case .clearNotifications: "ClearNotifications"
        case .clipboardInfo: "ClipboardInfo"
        case .contactInfo: "ContactInfo"
        case .conversationInfo: "ConversationInfo"
        case .deviceInfo: "DeviceInfo"
        case .disconnect: "Disconnect"
        case .dndState: "DndState"
        case .fileTransferInfo: "FileTransferInfo"
        case .mediaAction: "MediaAction"
        case .notificationAction: "NotificationAction"
        case .notificationInfo: "NotificationInfo"
        case .notificationReply: "NotificationReply"
        case .pairMessage: "PairMessage"
        case .playbackInfo: "PlaybackInfo"
        case .playSound: "PlaySound"
        case .requestApplicationList: "RequestApplicationList"
        case .requestWorkerLaunch: "RequestWorkerLaunch"
        case .ringerModeState: "RingerModeState"
        case .sftpServerInfo: "SftpServerInfo"
        case .textMessage: "TextMessage"
        case .threadRequest: "ThreadRequest"
        case .udpBroadcast: "UdpBroadcast"
        }
    }

    public static let allTypeNames: [String] = [
        "ActionInfo",
        "ActionList",
        "ApplicationInfo",
        "ApplicationList",
        "Authentication",
        "AudioAction",
        "AudioDeviceInfo",
        "AudioStreamState",
        "BatteryState",
        "BluetoothPairingRequest",
        "BluetoothPairingResult",
        "CallInfo",
        "CallLogInfo",
        "ClearNotifications",
        "ClipboardInfo",
        "ContactInfo",
        "ConversationInfo",
        "DeviceInfo",
        "Disconnect",
        "DndState",
        "FileTransferInfo",
        "MediaAction",
        "NotificationAction",
        "NotificationInfo",
        "NotificationReply",
        "PairMessage",
        "PlaybackInfo",
        "PlaySound",
        "RequestApplicationList",
        "RequestWorkerLaunch",
        "RingerModeState",
        "SftpServerInfo",
        "TextMessage",
        "ThreadRequest",
        "UdpBroadcast",
    ]
}

public enum SocketCodecError: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case invalidJSON
    case missingType
    case unknownType(String)
    case payloadMismatch(String)

    public var description: String {
        switch self {
        case .emptyInput: "Empty SocketMessage input"
        case .invalidJSON: "SocketMessage is not a JSON object"
        case .missingType: "SocketMessage is missing the `type` discriminator"
        case .unknownType(let name): "Unknown SocketMessage type: \(name)"
        case .payloadMismatch(let name): "Failed to decode payload for type \(name)"
        }
    }
}
