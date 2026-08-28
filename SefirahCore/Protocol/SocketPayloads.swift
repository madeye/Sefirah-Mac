import Foundation

// MARK: - Session / pairing

public struct RequestWorkerLaunch: Codable, Sendable, Equatable {
    public var command: String

    public init(command: String) {
        self.command = command
    }
}

public struct Authentication: Codable, Sendable, Equatable {
    public var deviceId: String
    public var deviceName: String
    public var publicKey: String
    public var model: String

    public init(deviceId: String, deviceName: String, publicKey: String, model: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.model = model
    }
}

public struct PairMessage: Codable, Sendable, Equatable {
    public var pair: Bool

    public init(pair: Bool) {
        self.pair = pair
    }
}

public struct BluetoothPairingResult: Codable, Sendable, Equatable {
    public var granted: Bool
    public var deviceName: String?

    public init(granted: Bool, deviceName: String? = nil) {
        self.granted = granted
        self.deviceName = deviceName
    }
}

public struct UdpBroadcast: Codable, Sendable, Equatable {
    public var port: Int
    public var deviceId: String
    public var deviceName: String

    public init(port: Int, deviceId: String, deviceName: String) {
        self.port = port
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}

public struct DeviceInfo: Codable, Sendable, Equatable {
    public var deviceName: String
    public var avatar: String?
    public var phoneNumbers: [PhoneNumber]

    public init(deviceName: String, avatar: String? = nil, phoneNumbers: [PhoneNumber] = []) {
        self.deviceName = deviceName
        self.avatar = avatar
        self.phoneNumbers = phoneNumbers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        phoneNumbers = try container.decodeIfPresent([PhoneNumber].self, forKey: .phoneNumbers) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case deviceName, avatar, phoneNumbers
    }
}

public struct BatteryState: Codable, Sendable, Equatable {
    public var batteryLevel: Int
    public var isCharging: Bool

    public init(batteryLevel: Int, isCharging: Bool) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }
}

public struct RingerModeState: Codable, Sendable, Equatable {
    public var mode: Int

    public init(mode: Int) {
        self.mode = mode
    }
}

public struct DndState: Codable, Sendable, Equatable {
    public var isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

public struct PlaySound: Codable, Sendable, Equatable {
    public var isPlaying: Bool

    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }
}

// MARK: - Calls

public struct CallInfo: Codable, Sendable, Equatable {
    public var callState: CallState
    public var phoneNumber: String
    public var contactInfo: ContactInfo?

    public init(callState: CallState, phoneNumber: String, contactInfo: ContactInfo? = nil) {
        self.callState = callState
        self.phoneNumber = phoneNumber
        self.contactInfo = contactInfo
    }
}

public struct CallLogInfo: Codable, Sendable, Equatable {
    public var callLogId: Int64
    public var phoneNumber: String
    public var timestampMillis: Int64
    public var durationSeconds: Int64
    public var callType: CallLogType
    public var contactInfo: ContactInfo?

    public init(
        callLogId: Int64,
        phoneNumber: String = "",
        timestampMillis: Int64,
        durationSeconds: Int64,
        callType: CallLogType,
        contactInfo: ContactInfo? = nil
    ) {
        self.callLogId = callLogId
        self.phoneNumber = phoneNumber
        self.timestampMillis = timestampMillis
        self.durationSeconds = durationSeconds
        self.callType = callType
        self.contactInfo = contactInfo
    }
}

public struct ContactInfo: Codable, Sendable, Equatable {
    public var id: String?
    public var lookupKey: String
    public var displayName: String
    public var number: String
    public var photoBase64: String

    public init(
        id: String? = nil,
        lookupKey: String,
        displayName: String,
        number: String,
        photoBase64: String = ""
    ) {
        self.id = id
        self.lookupKey = lookupKey
        self.displayName = displayName
        self.number = number
        self.photoBase64 = photoBase64
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        lookupKey = try container.decode(String.self, forKey: .lookupKey)
        displayName = try container.decode(String.self, forKey: .displayName)
        number = try container.decode(String.self, forKey: .number)
        photoBase64 = container.decodeDefault(forKey: .photoBase64, "")
    }

    enum CodingKeys: String, CodingKey {
        case id, lookupKey, displayName, number, photoBase64
    }
}

// MARK: - Audio / media

public struct AudioStreamState: Codable, Sendable, Equatable {
    public var streamType: AudioStreamType
    public var level: Int

    public init(streamType: AudioStreamType, level: Int) {
        self.streamType = streamType
        self.level = level
    }
}

public struct AudioDeviceInfo: Codable, Sendable, Equatable {
    public var infoType: AudioInfoType
    public var deviceId: String
    public var deviceName: String
    public var volume: Double
    public var isMuted: Bool
    public var isSelected: Bool

    public init(
        infoType: AudioInfoType,
        deviceId: String,
        deviceName: String = "",
        volume: Double,
        isMuted: Bool,
        isSelected: Bool
    ) {
        self.infoType = infoType
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.volume = volume
        self.isMuted = isMuted
        self.isSelected = isSelected
    }
}

public struct PlaybackInfo: Codable, Sendable, Equatable {
    public var infoType: PlaybackInfoType
    public var source: String
    public var trackTitle: String?
    public var artist: String?
    public var isPlaying: Bool
    public var isShuffleActive: Bool?
    public var repeatMode: Int?
    public var playbackRate: Double?
    public var position: Double?
    public var maxSeekTime: Double?
    public var minSeekTime: Double?
    public var thumbnail: String?
    public var appName: String?
    public var volume: Int
    public var canPlay: Bool?
    public var canPause: Bool?
    public var canGoNext: Bool?
    public var canGoPrevious: Bool?
    public var canSeek: Bool?

    public init(
        infoType: PlaybackInfoType,
        source: String,
        trackTitle: String? = nil,
        artist: String? = nil,
        isPlaying: Bool,
        isShuffleActive: Bool? = nil,
        repeatMode: Int? = nil,
        playbackRate: Double? = nil,
        position: Double? = nil,
        maxSeekTime: Double? = nil,
        minSeekTime: Double? = nil,
        thumbnail: String? = nil,
        appName: String? = nil,
        volume: Int = 0,
        canPlay: Bool? = nil,
        canPause: Bool? = nil,
        canGoNext: Bool? = nil,
        canGoPrevious: Bool? = nil,
        canSeek: Bool? = nil
    ) {
        self.infoType = infoType
        self.source = source
        self.trackTitle = trackTitle
        self.artist = artist
        self.isPlaying = isPlaying
        self.isShuffleActive = isShuffleActive
        self.repeatMode = repeatMode
        self.playbackRate = playbackRate
        self.position = position
        self.maxSeekTime = maxSeekTime
        self.minSeekTime = minSeekTime
        self.thumbnail = thumbnail
        self.appName = appName
        self.volume = volume
        self.canPlay = canPlay
        self.canPause = canPause
        self.canGoNext = canGoNext
        self.canGoPrevious = canGoPrevious
        self.canSeek = canSeek
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        infoType = try container.decode(PlaybackInfoType.self, forKey: .infoType)
        source = try container.decode(String.self, forKey: .source)
        trackTitle = try container.decodeIfPresent(String.self, forKey: .trackTitle)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        isPlaying = container.decodeDefault(forKey: .isPlaying, false)
        isShuffleActive = try container.decodeIfPresent(Bool.self, forKey: .isShuffleActive)
        repeatMode = try container.decodeIfPresent(Int.self, forKey: .repeatMode)
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
        position = try container.decodeIfPresent(Double.self, forKey: .position)
        maxSeekTime = try container.decodeIfPresent(Double.self, forKey: .maxSeekTime)
        minSeekTime = try container.decodeIfPresent(Double.self, forKey: .minSeekTime)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        volume = container.decodeDefault(forKey: .volume, 0)
        canPlay = try container.decodeIfPresent(Bool.self, forKey: .canPlay)
        canPause = try container.decodeIfPresent(Bool.self, forKey: .canPause)
        canGoNext = try container.decodeIfPresent(Bool.self, forKey: .canGoNext)
        canGoPrevious = try container.decodeIfPresent(Bool.self, forKey: .canGoPrevious)
        canSeek = try container.decodeIfPresent(Bool.self, forKey: .canSeek)
    }

    enum CodingKeys: String, CodingKey {
        case infoType, source, trackTitle, artist, isPlaying, isShuffleActive, repeatMode
        case playbackRate, position, maxSeekTime, minSeekTime, thumbnail, appName, volume
        case canPlay, canPause, canGoNext, canGoPrevious, canSeek
    }
}

public struct MediaAction: Codable, Sendable, Equatable {
    public var actionType: MediaActionType
    public var source: String
    public var value: Double?

    public init(actionType: MediaActionType, source: String, value: Double? = nil) {
        self.actionType = actionType
        self.source = source
        self.value = value
    }
}

public struct AudioAction: Codable, Sendable, Equatable {
    public var actionType: AudioActionType
    public var source: String
    public var value: Double?

    public init(actionType: AudioActionType, source: String, value: Double? = nil) {
        self.actionType = actionType
        self.source = source
        self.value = value
    }
}

// MARK: - SMS

public struct ConversationInfo: Codable, Sendable, Equatable {
    public var infoType: ConversationInfoType
    public var threadId: Int64
    public var recipients: [String]
    public var messages: [TextMessage]

    public init(
        infoType: ConversationInfoType,
        threadId: Int64,
        recipients: [String] = [],
        messages: [TextMessage] = []
    ) {
        self.infoType = infoType
        self.threadId = threadId
        self.recipients = recipients
        self.messages = messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        infoType = try container.decode(ConversationInfoType.self, forKey: .infoType)
        threadId = try container.decode(Int64.self, forKey: .threadId)
        recipients = container.decodeDefault(forKey: .recipients, [])
        messages = container.decodeDefault(forKey: .messages, [])
    }

    enum CodingKeys: String, CodingKey {
        case infoType, threadId, recipients, messages
    }
}

public struct TextMessage: Codable, Sendable, Equatable {
    public var uniqueId: Int64
    public var addresses: [String]
    public var threadId: Int64
    public var body: String
    public var timestamp: Int64
    public var messageType: Int
    public var read: Bool
    public var subscriptionId: Int
    public var attachments: [SmsAttachment]?
    public var isTextMessage: Bool
    public var hasMultipleRecipients: Bool

    public init(
        uniqueId: Int64 = 0,
        addresses: [String] = [],
        threadId: Int64,
        body: String,
        timestamp: Int64,
        messageType: Int,
        read: Bool = false,
        subscriptionId: Int = 0,
        attachments: [SmsAttachment]? = nil,
        isTextMessage: Bool = false,
        hasMultipleRecipients: Bool = false
    ) {
        self.uniqueId = uniqueId
        self.addresses = addresses
        self.threadId = threadId
        self.body = body
        self.timestamp = timestamp
        self.messageType = messageType
        self.read = read
        self.subscriptionId = subscriptionId
        self.attachments = attachments
        self.isTextMessage = isTextMessage
        self.hasMultipleRecipients = hasMultipleRecipients
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueId = container.decodeDefault(forKey: .uniqueId, 0)
        addresses = container.decodeDefault(forKey: .addresses, [])
        threadId = try container.decode(Int64.self, forKey: .threadId)
        body = container.decodeDefault(forKey: .body, "")
        timestamp = container.decodeDefault(forKey: .timestamp, 0)
        messageType = container.decodeDefault(forKey: .messageType, 0)
        read = container.decodeDefault(forKey: .read, false)
        subscriptionId = container.decodeDefault(forKey: .subscriptionId, 0)
        attachments = try container.decodeIfPresent([SmsAttachment].self, forKey: .attachments)
        isTextMessage = container.decodeDefault(forKey: .isTextMessage, false)
        hasMultipleRecipients = container.decodeDefault(forKey: .hasMultipleRecipients, false)
    }

    enum CodingKeys: String, CodingKey {
        case uniqueId, addresses, threadId, body, timestamp, messageType, read
        case subscriptionId, attachments, isTextMessage, hasMultipleRecipients
    }
}

public struct ThreadRequest: Codable, Sendable, Equatable {
    public var threadId: Int64
    public var rangeStartTimestamp: Int64
    public var numberToRequest: Int64

    public init(threadId: Int64, rangeStartTimestamp: Int64 = -1, numberToRequest: Int64 = -1) {
        self.threadId = threadId
        self.rangeStartTimestamp = rangeStartTimestamp
        self.numberToRequest = numberToRequest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(Int64.self, forKey: .threadId)
        rangeStartTimestamp = container.decodeDefault(forKey: .rangeStartTimestamp, -1)
        numberToRequest = container.decodeDefault(forKey: .numberToRequest, -1)
    }

    enum CodingKeys: String, CodingKey {
        case threadId, rangeStartTimestamp, numberToRequest
    }
}

// MARK: - Notifications

public struct NotificationInfo: Codable, Sendable, Equatable {
    public var notificationKey: String
    public var infoType: NotificationInfoType
    public var timestampMillis: Int64
    public var appPackage: String?
    public var appName: String?
    public var title: String?
    public var text: String?
    public var messages: [NotificationMessage]
    public var groupKey: String?
    public var tag: String?
    public var actions: [NotificationAction]
    public var replyResultKey: String?
    public var appIcon: String?
    public var largeIcon: String

    public init(
        notificationKey: String,
        infoType: NotificationInfoType,
        timestampMillis: Int64,
        appPackage: String? = nil,
        appName: String? = nil,
        title: String? = nil,
        text: String? = nil,
        messages: [NotificationMessage] = [],
        groupKey: String? = nil,
        tag: String? = nil,
        actions: [NotificationAction] = [],
        replyResultKey: String? = nil,
        appIcon: String? = nil,
        largeIcon: String = ""
    ) {
        self.notificationKey = notificationKey
        self.infoType = infoType
        self.timestampMillis = timestampMillis
        self.appPackage = appPackage
        self.appName = appName
        self.title = title
        self.text = text
        self.messages = messages
        self.groupKey = groupKey
        self.tag = tag
        self.actions = actions
        self.replyResultKey = replyResultKey
        self.appIcon = appIcon
        self.largeIcon = largeIcon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationKey = try container.decode(String.self, forKey: .notificationKey)
        infoType = try container.decode(NotificationInfoType.self, forKey: .infoType)
        timestampMillis = container.decodeDefault(forKey: .timestampMillis, 0)
        appPackage = try container.decodeIfPresent(String.self, forKey: .appPackage)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        messages = container.decodeDefault(forKey: .messages, [])
        groupKey = try container.decodeIfPresent(String.self, forKey: .groupKey)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        actions = container.decodeDefault(forKey: .actions, [])
        replyResultKey = try container.decodeIfPresent(String.self, forKey: .replyResultKey)
        appIcon = try container.decodeIfPresent(String.self, forKey: .appIcon)
        largeIcon = container.decodeDefault(forKey: .largeIcon, "")
    }

    enum CodingKeys: String, CodingKey {
        case notificationKey, infoType, timestampMillis, appPackage, appName, title, text
        case messages, groupKey, tag, actions, replyResultKey, appIcon, largeIcon
    }
}

public struct NotificationAction: Codable, Sendable, Equatable {
    public var notificationKey: String?
    public var label: String?
    public var actionIndex: Int

    public init(notificationKey: String? = nil, label: String? = "", actionIndex: Int) {
        self.notificationKey = notificationKey
        self.label = label
        self.actionIndex = actionIndex
    }
}

public struct NotificationReply: Codable, Sendable, Equatable {
    public var notificationKey: String
    public var replyResultKey: String
    public var replyText: String

    public init(notificationKey: String, replyResultKey: String, replyText: String) {
        self.notificationKey = notificationKey
        self.replyResultKey = replyResultKey
        self.replyText = replyText
    }
}

// MARK: - Files / clipboard / SFTP

public struct FileTransferInfo: Codable, Sendable, Equatable {
    public var files: [FileMetadata]
    public var serverInfo: ServerInfo
    public var isClipboard: Bool

    public init(files: [FileMetadata], serverInfo: ServerInfo, isClipboard: Bool = false) {
        self.files = files
        self.serverInfo = serverInfo
        self.isClipboard = isClipboard
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decode([FileMetadata].self, forKey: .files)
        serverInfo = try container.decode(ServerInfo.self, forKey: .serverInfo)
        isClipboard = container.decodeDefault(forKey: .isClipboard, false)
    }

    enum CodingKeys: String, CodingKey {
        case files, serverInfo, isClipboard
    }
}

public struct SftpServerInfo: Codable, Sendable, Equatable {
    public var username: String
    public var password: String
    public var port: Int
    public var paths: [String]
    public var pathNames: [String]

    public init(
        username: String,
        password: String,
        port: Int,
        paths: [String] = [],
        pathNames: [String] = []
    ) {
        self.username = username
        self.password = password
        self.port = port
        self.paths = paths
        self.pathNames = pathNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        port = try container.decode(Int.self, forKey: .port)
        paths = container.decodeDefault(forKey: .paths, [])
        pathNames = container.decodeDefault(forKey: .pathNames, [])
    }

    enum CodingKeys: String, CodingKey {
        case username, password, port, paths, pathNames
    }
}

public struct ClipboardInfo: Codable, Sendable, Equatable {
    public var clipboardType: String
    public var content: String

    public init(clipboardType: String, content: String) {
        self.clipboardType = clipboardType
        self.content = content
    }
}

// MARK: - Apps / actions

public struct ApplicationList: Codable, Sendable, Equatable {
    public var appList: [ApplicationInfo]

    public init(appList: [ApplicationInfo]) {
        self.appList = appList
    }
}

public struct ApplicationInfo: Codable, Sendable, Equatable {
    public var packageName: String
    public var appName: String
    public var appIcon: String?

    public init(packageName: String, appName: String, appIcon: String? = nil) {
        self.packageName = packageName
        self.appName = appName
        self.appIcon = appIcon
    }
}

public struct ActionInfo: Codable, Sendable, Equatable {
    public var actionId: String
    public var actionName: String
    public var icon: String?
    public var askForConfirmation: Bool

    public init(actionId: String, actionName: String, icon: String? = nil, askForConfirmation: Bool = false) {
        self.actionId = actionId
        self.actionName = actionName
        self.icon = icon
        self.askForConfirmation = askForConfirmation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actionId = try container.decode(String.self, forKey: .actionId)
        actionName = try container.decode(String.self, forKey: .actionName)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        askForConfirmation = container.decodeDefault(forKey: .askForConfirmation, false)
    }

    enum CodingKeys: String, CodingKey {
        case actionId, actionName, icon, askForConfirmation
    }
}

public struct ActionList: Codable, Sendable, Equatable {
    public var actions: [ActionInfo]

    public init(actions: [ActionInfo] = []) {
        self.actions = actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actions = container.decodeDefault(forKey: .actions, [])
    }

    enum CodingKeys: String, CodingKey {
        case actions
    }
}
