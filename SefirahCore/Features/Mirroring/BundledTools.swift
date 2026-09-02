import Foundation

/// Locations of the scrcpy helpers shipped inside Sefirah.app.
///
/// Mach-O helpers live in `Contents/MacOS` (nested code, signed with the app identity);
/// the device-side server and version file live in `Contents/Resources/scrcpy`.
public struct BundledTools: Sendable, Equatable {
    public var scrcpy: URL
    public var adb: URL
    public var server: URL
    public var version: String?

    public init(scrcpy: URL, adb: URL, server: URL, version: String?) {
        self.scrcpy = scrcpy
        self.adb = adb
        self.server = server
        self.version = version
    }

    /// nil if any of the three binaries is missing — callers report, never guess.
    public static func locate(in bundle: Bundle = .main, fileManager: FileManager = .default) -> BundledTools? {
        locate(
            auxiliaryExecutable: { bundle.url(forAuxiliaryExecutable: $0) },
            resourcesRoot: bundle.resourceURL,
            exists: { fileManager.fileExists(atPath: $0.path) },
            readVersion: { try? String(contentsOf: $0, encoding: .utf8) }
        )
    }

    /// Pure core used by `locate(in:)` and tests.
    static func locate(
        auxiliaryExecutable: (String) -> URL?,
        resourcesRoot: URL?,
        exists: (URL) -> Bool,
        readVersion: (URL) -> String?
    ) -> BundledTools? {
        guard let scrcpy = auxiliaryExecutable("scrcpy"), exists(scrcpy),
              let adb = auxiliaryExecutable("adb"), exists(adb),
              let resources = resourcesRoot
        else { return nil }
        let dir = resources.appendingPathComponent("scrcpy", isDirectory: true)
        let server = dir.appendingPathComponent("scrcpy-server")
        guard exists(server) else { return nil }
        let versionURL = dir.appendingPathComponent("VERSION")
        let version = readVersion(versionURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BundledTools(
            scrcpy: scrcpy,
            adb: adb,
            server: server,
            version: (version?.isEmpty ?? true) ? nil : version
        )
    }
}

/// The subset the native mirror needs: `adb` plus the device-side `scrcpy-server` (no scrcpy binary).
public struct NativeTools: Sendable, Equatable {
    public var adb: URL
    public var server: URL
    public var version: String?

    public init(adb: URL, server: URL, version: String?) {
        self.adb = adb
        self.server = server
        self.version = version
    }

    public static func locate(in bundle: Bundle = .main, fileManager: FileManager = .default) -> NativeTools? {
        locate(
            auxiliaryExecutable: { bundle.url(forAuxiliaryExecutable: $0) },
            resourcesRoot: bundle.resourceURL,
            exists: { fileManager.fileExists(atPath: $0.path) },
            readVersion: { try? String(contentsOf: $0, encoding: .utf8) }
        )
    }

    static func locate(
        auxiliaryExecutable: (String) -> URL?,
        resourcesRoot: URL?,
        exists: (URL) -> Bool,
        readVersion: (URL) -> String?
    ) -> NativeTools? {
        guard let adb = auxiliaryExecutable("adb"), exists(adb), let resources = resourcesRoot else { return nil }
        let dir = resources.appendingPathComponent("scrcpy", isDirectory: true)
        let server = dir.appendingPathComponent("scrcpy-server")
        guard exists(server) else { return nil }
        let version = readVersion(dir.appendingPathComponent("VERSION"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NativeTools(adb: adb, server: server, version: (version?.isEmpty ?? true) ? nil : version)
    }
}
