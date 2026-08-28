import Foundation
import GRDB

public struct AddressEntry: Codable, Sendable, Equatable {
    public var address: String
    public var isEnabled: Bool

    public init(address: String, isEnabled: Bool = true) {
        self.address = address
        self.isEnabled = isEnabled
    }
}

public struct LocalDeviceRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "LocalDeviceEntity"

    public var deviceId: String
    public var deviceName: String

    public init(deviceId: String, deviceName: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "DeviceId"
        case deviceName = "DeviceName"
    }
}

public struct PairedDeviceRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "PairedDeviceEntity"

    public var deviceId: String
    public var name: String
    public var model: String
    public var certificate: Data
    public var wallpaperBytes: Data?
    public var lastConnected: Date?
    public var addresses: [AddressEntry]
    public var callsTransportDeviceId: String?
    public var bluetoothAddress: String?
    public var bluetoothClassicDeviceId: String?
    public var phoneNumbers: [PhoneNumber]

    public init(
        deviceId: String,
        name: String,
        model: String,
        certificate: Data,
        wallpaperBytes: Data? = nil,
        lastConnected: Date? = nil,
        addresses: [AddressEntry] = [],
        callsTransportDeviceId: String? = nil,
        bluetoothAddress: String? = nil,
        bluetoothClassicDeviceId: String? = nil,
        phoneNumbers: [PhoneNumber] = []
    ) {
        self.deviceId = deviceId
        self.name = name
        self.model = model
        self.certificate = certificate
        self.wallpaperBytes = wallpaperBytes
        self.lastConnected = lastConnected
        self.addresses = addresses
        self.callsTransportDeviceId = callsTransportDeviceId
        self.bluetoothAddress = bluetoothAddress
        self.bluetoothClassicDeviceId = bluetoothClassicDeviceId
        self.phoneNumbers = phoneNumbers
    }

    public enum Columns {
        public static let deviceId = Column("DeviceId")
        public static let name = Column("Name")
        public static let model = Column("Model")
        public static let certificate = Column("Certificate")
        public static let wallpaperBytes = Column("WallpaperBytes")
        public static let lastConnected = Column("LastConnected")
        public static let addresses = Column("Addresses")
        public static let callsTransportDeviceId = Column("CallsTransportDeviceId")
        public static let bluetoothAddress = Column("BluetoothAddress")
        public static let bluetoothClassicDeviceId = Column("BluetoothClassicDeviceId")
        public static let phoneNumbers = Column("PhoneNumbers")
    }

    public init(row: Row) {
        deviceId = row[Columns.deviceId]
        name = row[Columns.name]
        model = row[Columns.model]
        certificate = row[Columns.certificate]
        wallpaperBytes = row[Columns.wallpaperBytes]
        lastConnected = row[Columns.lastConnected]
        let addressesJSON: String? = row[Columns.addresses]
        addresses = Self.decodeJSON(addressesJSON, as: [AddressEntry].self) ?? []
        callsTransportDeviceId = row[Columns.callsTransportDeviceId]
        bluetoothAddress = row[Columns.bluetoothAddress]
        bluetoothClassicDeviceId = row[Columns.bluetoothClassicDeviceId]
        let phonesJSON: String? = row[Columns.phoneNumbers]
        phoneNumbers = Self.decodeJSON(phonesJSON, as: [PhoneNumber].self) ?? []
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.deviceId] = deviceId
        container[Columns.name] = name
        container[Columns.model] = model
        container[Columns.certificate] = certificate
        container[Columns.wallpaperBytes] = wallpaperBytes
        container[Columns.lastConnected] = lastConnected
        container[Columns.addresses] = Self.encodeJSON(addresses)
        container[Columns.callsTransportDeviceId] = callsTransportDeviceId
        container[Columns.bluetoothAddress] = bluetoothAddress
        container[Columns.bluetoothClassicDeviceId] = bluetoothClassicDeviceId
        container[Columns.phoneNumbers] = Self.encodeJSON(phoneNumbers)
    }

    private static func decodeJSON<T: Decodable>(_ json: String?, as type: T.Type) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public struct ApplicationRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "ApplicationEntity"

    public var appKey: String
    public var deviceId: String
    public var packageName: String
    public var appName: String
    public var pinned: Bool
    public var filter: NotificationFilter

    public init(
        appKey: String,
        deviceId: String,
        packageName: String,
        appName: String,
        pinned: Bool = false,
        filter: NotificationFilter = .toastFeed
    ) {
        self.appKey = appKey
        self.deviceId = deviceId
        self.packageName = packageName
        self.appName = appName
        self.pinned = pinned
        self.filter = filter
    }

    enum CodingKeys: String, CodingKey {
        case appKey = "AppKey"
        case deviceId = "DeviceId"
        case packageName = "PackageName"
        case appName = "AppName"
        case pinned = "Pinned"
        case filter = "Filter"
    }
}

public struct ContactRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "ContactEntity"

    public var key: String
    public var deviceId: String
    public var contactId: String
    public var lookupKey: String
    public var displayName: String
    public var avatar: Data?

    public init(
        key: String,
        deviceId: String,
        contactId: String,
        lookupKey: String,
        displayName: String,
        avatar: Data? = nil
    ) {
        self.key = key
        self.deviceId = deviceId
        self.contactId = contactId
        self.lookupKey = lookupKey
        self.displayName = displayName
        self.avatar = avatar
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case deviceId = "DeviceId"
        case contactId = "ContactId"
        case lookupKey = "LookupKey"
        case displayName = "DisplayName"
        case avatar = "Avatar"
    }
}

public struct PhoneNumberRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "PhoneNumberEntity"

    public var key: String
    public var contactKey: String
    public var number: String

    public init(key: String, contactKey: String, number: String) {
        self.key = key
        self.contactKey = contactKey
        self.number = number
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case contactKey = "ContactKey"
        case number = "Number"
    }
}

public struct ConversationRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "ConversationEntity"

    public var key: String
    public var deviceId: String
    public var threadId: Int64
    public var addressesJSON: String?
    public var lastMessageTimestamp: Int64
    public var lastMessage: String?
    public var hasRead: Bool
    public var timeStamp: Int64

    public init(
        key: String,
        deviceId: String,
        threadId: Int64,
        addressesJSON: String? = nil,
        lastMessageTimestamp: Int64 = 0,
        lastMessage: String? = nil,
        hasRead: Bool = false,
        timeStamp: Int64 = 0
    ) {
        self.key = key
        self.deviceId = deviceId
        self.threadId = threadId
        self.addressesJSON = addressesJSON
        self.lastMessageTimestamp = lastMessageTimestamp
        self.lastMessage = lastMessage
        self.hasRead = hasRead
        self.timeStamp = timeStamp
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case deviceId = "DeviceId"
        case threadId = "ThreadId"
        case addressesJSON = "AddressesJson"
        case lastMessageTimestamp = "LastMessageTimestamp"
        case lastMessage = "LastMessage"
        case hasRead = "HasRead"
        case timeStamp = "TimeStamp"
    }
}

public struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "MessageEntity"

    public var key: String
    public var conversationKey: String
    public var deviceId: String
    public var uniqueId: Int64
    public var threadId: Int64
    public var body: String
    public var timestamp: Int64
    public var read: Bool
    public var subscriptionId: Int
    public var messageType: Int
    public var address: String

    public init(
        key: String,
        conversationKey: String,
        deviceId: String,
        uniqueId: Int64,
        threadId: Int64,
        body: String,
        timestamp: Int64,
        read: Bool,
        subscriptionId: Int,
        messageType: Int,
        address: String
    ) {
        self.key = key
        self.conversationKey = conversationKey
        self.deviceId = deviceId
        self.uniqueId = uniqueId
        self.threadId = threadId
        self.body = body
        self.timestamp = timestamp
        self.read = read
        self.subscriptionId = subscriptionId
        self.messageType = messageType
        self.address = address
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case conversationKey = "ConversationKey"
        case deviceId = "DeviceId"
        case uniqueId = "UniqueId"
        case threadId = "ThreadId"
        case body = "Body"
        case timestamp = "Timestamp"
        case read = "Read"
        case subscriptionId = "SubscriptionId"
        case messageType = "MessageType"
        case address = "Address"
    }
}

public struct AttachmentRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "AttachmentEntity"

    public var id: Int64?
    public var messageKey: String
    public var data: Data?

    public init(id: Int64? = nil, messageKey: String, data: Data?) {
        self.id = id
        self.messageKey = messageKey
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case messageKey = "MessageKey"
        case data = "Data"
    }
}

public struct CallLogRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "CallLogEntity"

    public var key: String
    public var deviceId: String
    public var callLogId: Int64
    public var phoneNumber: String
    public var timestampMillis: Int64
    public var durationSeconds: Int64
    public var callType: CallLogType

    public init(
        key: String,
        deviceId: String,
        callLogId: Int64,
        phoneNumber: String,
        timestampMillis: Int64,
        durationSeconds: Int64,
        callType: CallLogType
    ) {
        self.key = key
        self.deviceId = deviceId
        self.callLogId = callLogId
        self.phoneNumber = phoneNumber
        self.timestampMillis = timestampMillis
        self.durationSeconds = durationSeconds
        self.callType = callType
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case deviceId = "DeviceId"
        case callLogId = "CallLogId"
        case phoneNumber = "PhoneNumber"
        case timestampMillis = "TimestampMillis"
        case durationSeconds = "DurationSeconds"
        case callType = "CallType"
    }
}

public struct NotificationRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "NotificationEntity"

    public var key: String
    public var deviceId: String
    public var notificationKey: String
    public var pinned: Bool
    public var appPackage: String
    public var appName: String
    public var title: String?
    public var text: String?
    public var timestampMillis: Int64
    public var groupKey: String?
    public var tag: String?
    public var replyResultKey: String?
    public var largeIcon: Data?
    public var payloadJSON: String

    public init(
        key: String,
        deviceId: String,
        notificationKey: String,
        pinned: Bool = false,
        appPackage: String,
        appName: String,
        title: String? = nil,
        text: String? = nil,
        timestampMillis: Int64,
        groupKey: String? = nil,
        tag: String? = nil,
        replyResultKey: String? = nil,
        largeIcon: Data? = nil,
        payloadJSON: String = ""
    ) {
        self.key = key
        self.deviceId = deviceId
        self.notificationKey = notificationKey
        self.pinned = pinned
        self.appPackage = appPackage
        self.appName = appName
        self.title = title
        self.text = text
        self.timestampMillis = timestampMillis
        self.groupKey = groupKey
        self.tag = tag
        self.replyResultKey = replyResultKey
        self.largeIcon = largeIcon
        self.payloadJSON = payloadJSON
    }

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case deviceId = "DeviceId"
        case notificationKey = "NotificationKey"
        case pinned = "Pinned"
        case appPackage = "AppPackage"
        case appName = "AppName"
        case title = "Title"
        case text = "Text"
        case timestampMillis = "TimestampMillis"
        case groupKey = "GroupKey"
        case tag = "Tag"
        case replyResultKey = "ReplyResultKey"
        case largeIcon = "LargeIcon"
        case payloadJSON = "PayloadJson"
    }
}

public struct SchemaVersionRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "SchemaVersionEntity"
    public var version: Int

    public init(version: Int) {
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case version = "Version"
    }
}
