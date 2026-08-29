import Foundation

public enum ScrcpyLaunchError: Error, Equatable, LocalizedError {
    /// No bundled tools and no override.
    case scrcpyUnavailable
    /// The user set a path that is not an executable file.
    case overrideNotFound(tool: String, path: String)
    /// Bundle damaged: "scrcpy" | "adb" | "scrcpy-server".
    case bundledToolMissing(String)

    public var errorDescription: String? {
        switch self {
        case .scrcpyUnavailable:
            return "Bundled scrcpy is missing and no custom scrcpy path is set. Reinstall Sefirah or set a scrcpy path in Settings."
        case .overrideNotFound(let tool, let path):
            return "\(tool) path '\(path)' is not an executable file. Clear it in Settings to use the bundled copy."
        case .bundledToolMissing(let tool):
            return "Bundled scrcpy is missing (\(tool)). Reinstall Sefirah."
        }
    }
}

public struct ScrcpyLaunchPlan: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    /// What adb the plan uses (nil = let scrcpy search PATH).
    public var adb: URL?
    public var usesBundledScrcpy: Bool

    public init(executable: URL, arguments: [String], environment: [String: String], adb: URL?, usesBundledScrcpy: Bool) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.adb = adb
        self.usesBundledScrcpy = usesBundledScrcpy
    }
}

public enum ScrcpyLaunchPlanner {
    public static let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    public static func plan(
        general: GeneralSettings,
        device: DeviceSettings,
        bundled: BundledTools?,
        serial: String?,
        package: String? = nil,
        appName: String? = nil,
        baseEnvironment: [String: String],
        home: String,
        isExecutable: (URL) -> Bool
    ) throws -> ScrcpyLaunchPlan {
        let scrcpyOverride = firstNonEmpty(general.scrcpyPath, device.scrcpyPath)
        let adbOverride = firstNonEmpty(general.adbPath, device.adbPath)

        let executable: URL
        let usesBundled: Bool
        if let scrcpyOverride {
            let url = URL(fileURLWithPath: scrcpyOverride)
            guard isExecutable(url) else {
                throw ScrcpyLaunchError.overrideNotFound(tool: "scrcpy", path: scrcpyOverride)
            }
            executable = url
            usesBundled = false
        } else if let bundled {
            guard isExecutable(bundled.scrcpy) else { throw ScrcpyLaunchError.bundledToolMissing("scrcpy") }
            executable = bundled.scrcpy
            usesBundled = true
        } else {
            throw ScrcpyLaunchError.scrcpyUnavailable
        }

        var adb: URL?
        if let adbOverride {
            let url = URL(fileURLWithPath: adbOverride)
            guard isExecutable(url) else {
                throw ScrcpyLaunchError.overrideNotFound(tool: "adb", path: adbOverride)
            }
            adb = url
        } else if let bundled {
            guard isExecutable(bundled.adb) else { throw ScrcpyLaunchError.bundledToolMissing("adb") }
            adb = bundled.adb
        }

        var environment = baseEnvironment
        if environment["HOME"] == nil { environment["HOME"] = home }
        if environment["PATH"] == nil { environment["PATH"] = defaultPath }
        if let adb { environment["ADB"] = adb.path }
        if usesBundled, let bundled {
            environment["SCRCPY_SERVER_PATH"] = bundled.server.path
        }

        return ScrcpyLaunchPlan(
            executable: executable,
            arguments: ScrcpyArguments.build(settings: device, serial: serial, package: package, appName: appName),
            environment: environment,
            adb: adb,
            usesBundledScrcpy: usesBundled
        )
    }

    private static func firstNonEmpty(_ values: String...) -> String? {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
