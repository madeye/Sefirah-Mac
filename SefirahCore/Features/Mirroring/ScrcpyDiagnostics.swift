import Foundation

public enum ScrcpyDiagnostics {
    /// Maps scrcpy/adb stderr to a one-line, actionable hint; nil if unrecognised.
    public static func hint(exit: ScrcpyExit) -> String? {
        switch exit {
        case .normal:
            return nil
        case .signaled(let signal, let stderr):
            if signal == 9 {
                return "macOS refused to run the bundled scrcpy (code signature). Reinstall Sefirah."
            }
            return hint(stderr: stderr)
        case .failure(_, let stderr):
            return hint(stderr: stderr)
        }
    }

    static func hint(stderr: String) -> String? {
        let text = stderr.lowercased()
        if text.contains("no devices/emulators found") || text.contains("could not find any adb device") {
            return "No Android device is visible to adb. Connect it over USB with USB debugging enabled, or enable Wireless debugging."
        }
        if text.contains("unauthorized") {
            return "Accept the USB-debugging prompt on the phone."
        }
        if text.contains("more than one device") {
            return "Several devices are connected; set a device preference or add `-s <serial>` to custom arguments."
        }
        if text.contains("server version") {
            return "scrcpy-server does not match the scrcpy binary (custom scrcpy path?)."
        }
        if text.contains("device offline") {
            return "adb reports the device offline; replug or run `adb reconnect`."
        }
        return nil
    }
}
