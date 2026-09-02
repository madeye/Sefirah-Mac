import Foundation

public enum MirrorDiagnostics {
    /// One-line, actionable hint for a failed session; nil when the title says it all.
    public static func hint(_ error: MirrorError) -> String? {
        switch error {
        case .toolsMissing:
            return "Reinstall Sefirah, or switch the mirror backend to external scrcpy with a custom path."
        case .adb(let adbError):
            switch adbError {
            case .commandFailed(_, _, let stderr):
                let text = stderr.lowercased()
                if text.contains("unauthorized") { return "Accept the USB debugging prompt on the phone." }
                if text.contains("offline") || text.contains("not found") || text.contains("no devices") {
                    return "Reconnect Wi-Fi ADB (Settings ▸ Restart ADB server) or plug the phone in over USB."
                }
                return nil
            case .connectFailed, .noUsbDeviceForTcpip:
                return "Enable Wireless debugging, or connect once over USB so Sefirah can switch the phone to TCP/IP mode."
            case .timeout:
                return "adb did not respond; try Settings ▸ Restart ADB server."
            case .spawnFailed:
                return "The bundled adb could not be started. Reinstall Sefirah."
            }
        case .noDevice:
            return "No Android device is visible to adb. Enable Wireless debugging or connect over USB."
        case .invalidOptions:
            return "Fix the mirroring settings for this device."
        case .versionMismatch:
            return "The bundled scrcpy-server does not match — run scripts/fetch-scrcpy.sh."
        case .serverExited(_, let log):
            let text = log.lowercased()
            if text.contains("could not find") || text.contains("permission denied") { return "adb shell is blocked on this device." }
            if text.contains("does not match") { return "The bundled scrcpy-server does not match — run scripts/fetch-scrcpy.sh." }
            return "See the server log (Copy log)."
        case .handshakeTimeout(let stage):
            switch stage {
            case .dummyByte: return "The server did not start (see log)."
            default: return "The phone stopped responding during setup."
            }
        case .videoConfigError:
            return "Encoder failed — lower the resolution or bitrate, or switch the video codec."
        case .audioConfigError:
            return "Audio capture failed — try another audio codec or disable audio forwarding."
        case .unsupportedVideoCodec:
            return "Choose H.264 or H.265 in the device settings."
        case .unsupportedAudioCodec:
            return "Choose Opus, AAC or raw audio in the device settings."
        case .decoderFailed:
            return "Try restarting the mirror; if it persists, switch the video codec."
        case .connectionLost:
            return "Check the Wi-Fi ADB connection and try again."
        case .protocolError, .serverSpawnFailed, .cancelled:
            return nil
        }
    }
}
