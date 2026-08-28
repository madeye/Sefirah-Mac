import Foundation

/// Nested DTOs that appear inside SocketMessage payloads.
/// These are NOT polymorphic on the wire (no `type` field) even when the C#
/// class also extends `SocketMessage`.

public struct PhoneNumber: Codable, Sendable, Equatable {
    public var number: String
    public var subscriptionId: Int

    public init(number: String, subscriptionId: Int) {
        self.number = number
        self.subscriptionId = subscriptionId
    }
}

public struct FileMetadata: Codable, Sendable, Equatable {
    public var fileName: String
    public var mimeType: String
    public var fileSize: Int64

    public init(fileName: String, mimeType: String, fileSize: Int64) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
    }
}

public struct ServerInfo: Codable, Sendable, Equatable {
    public var port: Int

    public init(port: Int) {
        self.port = port
    }
}

public struct SmsAttachment: Codable, Sendable, Equatable {
    public var id: String?
    public var mimeType: String?
    public var base64EncodedFile: String?

    public init(id: String? = nil, mimeType: String? = nil, base64EncodedFile: String? = nil) {
        self.id = id
        self.mimeType = mimeType
        self.base64EncodedFile = base64EncodedFile
    }
}

public struct NotificationMessage: Codable, Sendable, Equatable {
    public var sender: String
    public var text: String

    public init(sender: String, text: String) {
        self.sender = sender
        self.text = text
    }
}
