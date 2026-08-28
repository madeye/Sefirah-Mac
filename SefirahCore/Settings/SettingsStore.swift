import Foundation

public enum SettingsError: Error, Equatable {
    case encodingFailed
    case decodingFailed
}

/// JSON settings on disk. General file plus one file per paired device.
public final class SettingsStore: @unchecked Sendable {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public var generalURL: URL {
        directory.appendingPathComponent("general.json")
    }

    public func deviceURL(_ deviceId: String) -> URL {
        directory.appendingPathComponent("devices").appendingPathComponent("\(deviceId).json")
    }

    public func loadGeneral() throws -> GeneralSettings {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: generalURL.path) else {
            return GeneralSettings()
        }
        do {
            let data = try Data(contentsOf: generalURL)
            return try decoder.decode(GeneralSettings.self, from: data)
        } catch {
            throw SettingsError.decodingFailed
        }
    }

    public func saveGeneral(_ settings: GeneralSettings) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let data = try encoder.encode(settings)
            try data.write(to: generalURL, options: .atomic)
        } catch {
            throw SettingsError.encodingFailed
        }
    }

    public func loadDevice(id: String) throws -> DeviceSettings {
        lock.lock()
        defer { lock.unlock() }
        let url = deviceURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DeviceSettings(deviceId: id)
        }
        do {
            let data = try Data(contentsOf: url)
            var settings = try decoder.decode(DeviceSettings.self, from: data)
            settings.deviceId = id
            settings.clampBatteryThreshold()
            return settings
        } catch {
            throw SettingsError.decodingFailed
        }
    }

    public func saveDevice(_ settings: DeviceSettings) throws {
        lock.lock()
        defer { lock.unlock() }
        var copy = settings
        copy.clampBatteryThreshold()
        let url = deviceURL(copy.deviceId)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let data = try encoder.encode(copy)
            try data.write(to: url, options: .atomic)
        } catch {
            throw SettingsError.encodingFailed
        }
    }
}
