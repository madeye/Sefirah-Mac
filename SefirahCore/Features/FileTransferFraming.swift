import Foundation

/// Control-plane words for the file-transfer data socket.
/// C# sender compares equality to `"start"` / `"complete"` without requiring a newline;
/// the client typically writes `"start\n"` / `"complete\n"`.
public enum FileTransferFraming {
    public static let startToken = "start"
    public static let completeToken = "complete"
    public static let chunkSize = 524_288

    public enum Control: Equatable, Sendable {
        case start
        case complete
    }

    public static func encodeStart() -> Data { Data("start\n".utf8) }
    public static func encodeComplete() -> Data { Data("complete\n".utf8) }

    public static func parseControl(_ data: Data) -> Control? {
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch text {
        case startToken: return .start
        case completeToken: return .complete
        default: return nil
        }
    }
}

/// Receiver-side state machine for one `FileTransferInfo` payload (no TLS).
/// After `begin()`, the peer streams raw bytes sized by each file's `fileSize`.
public final class FileReceiveEngine: @unchecked Sendable {
    public let files: [FileMetadata]
    public let destination: URL
    public private(set) var completedURLs: [URL] = []

    private var index = 0
    private var received: Int64 = 0
    private var fileBuffer = Data()

    public init(files: [FileMetadata], destination: URL) {
        self.files = files
        self.destination = destination
    }

    public var currentFile: FileMetadata? {
        index < files.count ? files[index] : nil
    }

    public var isFinished: Bool { index >= files.count }

    public var remaining: Int64 {
        guard let file = currentFile else { return 0 }
        return max(0, file.fileSize - received)
    }

    public func beginSignal() -> Data {
        FileTransferFraming.encodeStart()
    }

    /// Ingest a raw data-plane chunk. When a file reaches `fileSize`, it is written
    /// and `.fileComplete` is returned so the caller can send `complete` (then `start` for the next file).
    public func ingest(_ chunk: Data) throws -> FileReceiveStep {
        guard let file = currentFile else { return .allComplete }
        fileBuffer.append(chunk)
        received = Int64(fileBuffer.count)
        if received < file.fileSize {
            return .waitingForMore(received: received, total: file.fileSize)
        }
        if received > file.fileSize {
            throw FileTransferError.sizeMismatch(expected: file.fileSize, actual: received)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = uniqueURL(for: file.fileName)
        try fileBuffer.write(to: url)
        completedURLs.append(url)
        fileBuffer.removeAll(keepingCapacity: false)
        received = 0
        index += 1
        if index >= files.count {
            return .allComplete
        }
        return .fileComplete(name: file.fileName, nextStart: FileTransferFraming.encodeStart())
    }

    public func completeSignal() -> Data {
        FileTransferFraming.encodeComplete()
    }

    private func uniqueURL(for fileName: String) -> URL {
        var url = destination.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        repeat {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            url = destination.appendingPathComponent(name)
            n += 1
        } while FileManager.default.fileExists(atPath: url.path)
        return url
    }
}

public enum FileReceiveStep: Equatable, Sendable {
    case waitingForMore(received: Int64, total: Int64)
    case fileComplete(name: String, nextStart: Data)
    case allComplete
}

public enum FileTransferError: Error, Equatable {
    case sizeMismatch(expected: Int64, actual: Int64)
    case unexpectedEOF
}

/// Duplex byte pipe used by the file-transfer data plane (`start` / raw bytes / `complete`).
public protocol FileTransferIO: AnyObject, Sendable {
    func write(_ data: Data) async throws
    func read(maxLength: Int) async throws -> Data
}

/// Drives `FileReceiveEngine` over a byte pipe the same way the C# receiver talks to the phone.
public enum FileTransferSession {
    public static func receive(
        files: [FileMetadata],
        destination: URL,
        io: FileTransferIO
    ) async throws -> [URL] {
        let engine = FileReceiveEngine(files: files, destination: destination)
        while !engine.isFinished {
            try await io.write(engine.beginSignal())
            if engine.remaining == 0 {
                _ = try engine.ingest(Data())
                try await io.write(engine.completeSignal())
                continue
            }
            fileLoop: while engine.remaining > 0 {
                let toRead = min(FileTransferFraming.chunkSize, Int(engine.remaining))
                let chunk = try await io.read(maxLength: max(1, toRead))
                if chunk.isEmpty { throw FileTransferError.unexpectedEOF }
                switch try engine.ingest(chunk) {
                case .waitingForMore:
                    continue
                case .fileComplete, .allComplete:
                    try await io.write(engine.completeSignal())
                    break fileLoop
                }
            }
        }
        return engine.completedURLs
    }
}
