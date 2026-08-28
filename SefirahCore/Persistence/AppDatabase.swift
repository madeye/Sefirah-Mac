import Foundation
import GRDB

public struct AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(5)
        dbQueue = try DatabaseQueue(path: fileURL.path, configuration: config)
        try migrator.migrate(dbQueue)
    }

    public init(inMemory: Void) throws {
        dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
    }

    public var schemaVersion: Int {
        (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT Version FROM SchemaVersionEntity ORDER BY Version DESC")
        }) ?? 0
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v5") { db in
            try db.execute(sql: """
                CREATE TABLE SchemaVersionEntity (
                    Version INTEGER PRIMARY KEY NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE LocalDeviceEntity (
                    DeviceId TEXT PRIMARY KEY NOT NULL,
                    DeviceName TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE PairedDeviceEntity (
                    DeviceId TEXT PRIMARY KEY NOT NULL,
                    Name TEXT NOT NULL,
                    Model TEXT NOT NULL,
                    Certificate BLOB NOT NULL,
                    WallpaperBytes BLOB,
                    LastConnected DATETIME,
                    Addresses TEXT,
                    CallsTransportDeviceId TEXT,
                    BluetoothAddress TEXT,
                    BluetoothClassicDeviceId TEXT,
                    PhoneNumbers TEXT
                )
                """)
            try db.execute(sql: """
                CREATE TABLE ApplicationEntity (
                    AppKey TEXT PRIMARY KEY NOT NULL,
                    DeviceId TEXT NOT NULL,
                    PackageName TEXT NOT NULL,
                    AppName TEXT NOT NULL,
                    Pinned INTEGER NOT NULL DEFAULT 0,
                    Filter INTEGER NOT NULL DEFAULT 2
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_application_device ON ApplicationEntity(DeviceId)")
            try db.execute(sql: "CREATE INDEX idx_application_package ON ApplicationEntity(PackageName)")
            try db.execute(sql: """
                CREATE TABLE ContactEntity (
                    Key TEXT PRIMARY KEY NOT NULL,
                    DeviceId TEXT NOT NULL,
                    ContactId TEXT NOT NULL,
                    LookupKey TEXT NOT NULL,
                    DisplayName TEXT NOT NULL,
                    Avatar BLOB
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_contact_device ON ContactEntity(DeviceId)")
            try db.execute(sql: """
                CREATE TABLE PhoneNumberEntity (
                    Key TEXT PRIMARY KEY NOT NULL,
                    ContactKey TEXT NOT NULL,
                    Number TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_phone_contact ON PhoneNumberEntity(ContactKey)")
            try db.execute(sql: """
                CREATE TABLE ConversationEntity (
                    Key TEXT PRIMARY KEY NOT NULL,
                    DeviceId TEXT NOT NULL,
                    ThreadId INTEGER NOT NULL,
                    AddressesJson TEXT,
                    LastMessageTimestamp INTEGER NOT NULL DEFAULT 0,
                    LastMessage TEXT,
                    HasRead INTEGER NOT NULL DEFAULT 0,
                    TimeStamp INTEGER NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_conversation_device ON ConversationEntity(DeviceId)")
            try db.execute(sql: """
                CREATE TABLE MessageEntity (
                    Key TEXT PRIMARY KEY NOT NULL,
                    ConversationKey TEXT NOT NULL,
                    DeviceId TEXT NOT NULL,
                    UniqueId INTEGER NOT NULL,
                    ThreadId INTEGER NOT NULL,
                    Body TEXT NOT NULL,
                    Timestamp INTEGER NOT NULL,
                    Read INTEGER NOT NULL DEFAULT 0,
                    SubscriptionId INTEGER NOT NULL DEFAULT 0,
                    MessageType INTEGER NOT NULL DEFAULT 1,
                    Address TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_message_conversation ON MessageEntity(ConversationKey)")
            try db.execute(sql: "CREATE INDEX idx_message_device ON MessageEntity(DeviceId)")
            try db.execute(sql: """
                CREATE TABLE AttachmentEntity (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    MessageKey TEXT NOT NULL,
                    Data BLOB
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_attachment_message ON AttachmentEntity(MessageKey)")
            try db.execute(sql: """
                CREATE TABLE CallLogEntity (
                    Key TEXT PRIMARY KEY NOT NULL,
                    DeviceId TEXT NOT NULL,
                    CallLogId INTEGER NOT NULL,
                    PhoneNumber TEXT NOT NULL,
                    TimestampMillis INTEGER NOT NULL,
                    DurationSeconds INTEGER NOT NULL,
                    CallType TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_calllog_device ON CallLogEntity(DeviceId)")
            try db.execute(sql: """
                CREATE TABLE NotificationEntity (
                    Key TEXT PRIMARY KEY NOT NULL,
                    DeviceId TEXT NOT NULL,
                    NotificationKey TEXT NOT NULL,
                    Pinned INTEGER NOT NULL DEFAULT 0,
                    AppPackage TEXT NOT NULL,
                    AppName TEXT NOT NULL,
                    Title TEXT,
                    Text TEXT,
                    TimestampMillis INTEGER NOT NULL,
                    GroupKey TEXT,
                    Tag TEXT,
                    ReplyResultKey TEXT,
                    LargeIcon BLOB,
                    PayloadJson TEXT NOT NULL DEFAULT ''
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_notification_device ON NotificationEntity(DeviceId)")
            try db.execute(sql: "INSERT INTO SchemaVersionEntity (Version) VALUES (5)")
        }
        return migrator
    }
}
