import Foundation

/// NDJSON control-channel codec.
///
/// C# writes `JsonSerializer.Serialize(message) + "\n"` as UTF-8, with:
/// - `PropertyNamingPolicy = JsonNamingPolicy.CamelCase`
/// - polymorphic discriminator property `"type"` = PascalCase class name
/// - `JsonStringEnumConverter` (PascalCase) except `AudioStreamType` (integer)
public enum NDJSONCodec {
    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()

    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = []
        return encoder
    }()

    // MARK: - Single message

    public static func decodeMessage(from json: String) throws -> SocketMessage {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SocketCodecError.emptyInput }
        guard let data = trimmed.data(using: .utf8) else { throw SocketCodecError.invalidJSON }
        return try decodeMessage(from: data)
    }

    public static func decodeMessage(from data: Data) throws -> SocketMessage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocketCodecError.invalidJSON
        }
        guard let type = object["type"] as? String, !type.isEmpty else {
            throw SocketCodecError.missingType
        }
        return try decode(type: type, data: data)
    }

    public static func encodeMessage(_ message: SocketMessage) throws -> Data {
        var object: [String: Any] = ["type": message.typeName]
        if let payload = try encodePayloadDictionary(message) {
            for (key, value) in payload {
                object[key] = value
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [])
    }

    /// UTF-8 JSON plus a trailing newline, matching `NetworkService.EncodeMessage`.
    public static func encodeLine(_ message: SocketMessage) throws -> Data {
        var data = try encodeMessage(message)
        data.append(0x0A)
        return data
    }

    // MARK: - Framing

    /// Pull complete newline-delimited JSON objects out of `buffer`, leaving any
    /// incomplete trailing fragment in place. Matches `GetMessagesFromBuffer`.
    public static func popCompleteLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let slice = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if let line = String(data: slice, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }
        }
        return lines
    }

    public static func decodeLines(from buffer: inout Data) throws -> [SocketMessage] {
        try popCompleteLines(from: &buffer).map { try decodeMessage(from: $0) }
    }

    // MARK: - Internals

    private static func encodePayloadDictionary(_ message: SocketMessage) throws -> [String: Any]? {
        let data: Data?
        switch message {
        case .disconnect, .clearNotifications, .requestApplicationList, .bluetoothPairingRequest:
            return nil
        case .actionInfo(let value): data = try jsonEncoder.encode(value)
        case .actionList(let value): data = try jsonEncoder.encode(value)
        case .applicationInfo(let value): data = try jsonEncoder.encode(value)
        case .applicationList(let value): data = try jsonEncoder.encode(value)
        case .authentication(let value): data = try jsonEncoder.encode(value)
        case .audioAction(let value): data = try jsonEncoder.encode(value)
        case .audioDeviceInfo(let value): data = try jsonEncoder.encode(value)
        case .audioStreamState(let value): data = try jsonEncoder.encode(value)
        case .batteryState(let value): data = try jsonEncoder.encode(value)
        case .bluetoothPairingResult(let value): data = try jsonEncoder.encode(value)
        case .callInfo(let value): data = try jsonEncoder.encode(value)
        case .callLogInfo(let value): data = try jsonEncoder.encode(value)
        case .clipboardInfo(let value): data = try jsonEncoder.encode(value)
        case .contactInfo(let value): data = try jsonEncoder.encode(value)
        case .conversationInfo(let value): data = try jsonEncoder.encode(value)
        case .deviceInfo(let value): data = try jsonEncoder.encode(value)
        case .dndState(let value): data = try jsonEncoder.encode(value)
        case .fileTransferInfo(let value): data = try jsonEncoder.encode(value)
        case .mediaAction(let value): data = try jsonEncoder.encode(value)
        case .notificationAction(let value): data = try jsonEncoder.encode(value)
        case .notificationInfo(let value): data = try jsonEncoder.encode(value)
        case .notificationReply(let value): data = try jsonEncoder.encode(value)
        case .pairMessage(let value): data = try jsonEncoder.encode(value)
        case .playbackInfo(let value): data = try jsonEncoder.encode(value)
        case .playSound(let value): data = try jsonEncoder.encode(value)
        case .requestWorkerLaunch(let value): data = try jsonEncoder.encode(value)
        case .ringerModeState(let value): data = try jsonEncoder.encode(value)
        case .sftpServerInfo(let value): data = try jsonEncoder.encode(value)
        case .textMessage(let value): data = try jsonEncoder.encode(value)
        case .threadRequest(let value): data = try jsonEncoder.encode(value)
        case .udpBroadcast(let value): data = try jsonEncoder.encode(value)
        }
        guard let data else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SocketCodecError.invalidJSON
        }
        return object
    }

    private static func decode(type: String, data: Data) throws -> SocketMessage {
        do {
            switch type {
            case "Disconnect": return .disconnect
            case "ClearNotifications": return .clearNotifications
            case "RequestApplicationList": return .requestApplicationList
            case "BluetoothPairingRequest": return .bluetoothPairingRequest
            case "ActionInfo": return .actionInfo(try jsonDecoder.decode(ActionInfo.self, from: data))
            case "ActionList": return .actionList(try jsonDecoder.decode(ActionList.self, from: data))
            case "ApplicationInfo": return .applicationInfo(try jsonDecoder.decode(ApplicationInfo.self, from: data))
            case "ApplicationList": return .applicationList(try jsonDecoder.decode(ApplicationList.self, from: data))
            case "Authentication": return .authentication(try jsonDecoder.decode(Authentication.self, from: data))
            case "AudioAction": return .audioAction(try jsonDecoder.decode(AudioAction.self, from: data))
            case "AudioDeviceInfo": return .audioDeviceInfo(try jsonDecoder.decode(AudioDeviceInfo.self, from: data))
            case "AudioStreamState": return .audioStreamState(try jsonDecoder.decode(AudioStreamState.self, from: data))
            case "BatteryState": return .batteryState(try jsonDecoder.decode(BatteryState.self, from: data))
            case "BluetoothPairingResult":
                return .bluetoothPairingResult(try jsonDecoder.decode(BluetoothPairingResult.self, from: data))
            case "CallInfo": return .callInfo(try jsonDecoder.decode(CallInfo.self, from: data))
            case "CallLogInfo": return .callLogInfo(try jsonDecoder.decode(CallLogInfo.self, from: data))
            case "ClipboardInfo": return .clipboardInfo(try jsonDecoder.decode(ClipboardInfo.self, from: data))
            case "ContactInfo": return .contactInfo(try jsonDecoder.decode(ContactInfo.self, from: data))
            case "ConversationInfo": return .conversationInfo(try jsonDecoder.decode(ConversationInfo.self, from: data))
            case "DeviceInfo": return .deviceInfo(try jsonDecoder.decode(DeviceInfo.self, from: data))
            case "DndState": return .dndState(try jsonDecoder.decode(DndState.self, from: data))
            case "FileTransferInfo": return .fileTransferInfo(try jsonDecoder.decode(FileTransferInfo.self, from: data))
            case "MediaAction": return .mediaAction(try jsonDecoder.decode(MediaAction.self, from: data))
            case "NotificationAction":
                return .notificationAction(try jsonDecoder.decode(NotificationAction.self, from: data))
            case "NotificationInfo": return .notificationInfo(try jsonDecoder.decode(NotificationInfo.self, from: data))
            case "NotificationReply":
                return .notificationReply(try jsonDecoder.decode(NotificationReply.self, from: data))
            case "PairMessage": return .pairMessage(try jsonDecoder.decode(PairMessage.self, from: data))
            case "PlaybackInfo": return .playbackInfo(try jsonDecoder.decode(PlaybackInfo.self, from: data))
            case "PlaySound": return .playSound(try jsonDecoder.decode(PlaySound.self, from: data))
            case "RequestWorkerLaunch":
                return .requestWorkerLaunch(try jsonDecoder.decode(RequestWorkerLaunch.self, from: data))
            case "RingerModeState": return .ringerModeState(try jsonDecoder.decode(RingerModeState.self, from: data))
            case "SftpServerInfo": return .sftpServerInfo(try jsonDecoder.decode(SftpServerInfo.self, from: data))
            case "TextMessage": return .textMessage(try jsonDecoder.decode(TextMessage.self, from: data))
            case "ThreadRequest": return .threadRequest(try jsonDecoder.decode(ThreadRequest.self, from: data))
            case "UdpBroadcast": return .udpBroadcast(try jsonDecoder.decode(UdpBroadcast.self, from: data))
            default:
                throw SocketCodecError.unknownType(type)
            }
        } catch let error as SocketCodecError {
            throw error
        } catch {
            throw SocketCodecError.payloadMismatch(type)
        }
    }
}
