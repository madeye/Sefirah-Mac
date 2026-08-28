import SefirahCore
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testGeneralDefaultsAndRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sefirah-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)
        let fresh = try store.loadGeneral()
        XCTAssertEqual(fresh.startupOption, .inTray)
        XCTAssertEqual(fresh.theme, .default)
        XCTAssertTrue(fresh.actions.isEmpty)

        var updated = fresh
        updated.theme = .dark
        updated.scrcpyPath = "/opt/homebrew/bin/scrcpy"
        updated.actions = [ActionItem(name: "Lock", actionId: "power")]
        try store.saveGeneral(updated)

        let loaded = try store.loadGeneral()
        XCTAssertEqual(loaded.theme, .dark)
        XCTAssertEqual(loaded.scrcpyPath, "/opt/homebrew/bin/scrcpy")
        XCTAssertEqual(loaded.actions.first?.actionId, "power")
    }

    func testDeviceSettingsClampBatteryThreshold() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sefirah-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)
        var settings = DeviceSettings(deviceId: "phone-1")
        XCTAssertEqual(settings.lowBatteryAlertThreshold, 20)
        settings.lowBatteryAlertThreshold = 99
        try store.saveDevice(settings)
        let loaded = try store.loadDevice(id: "phone-1")
        XCTAssertEqual(loaded.lowBatteryAlertThreshold, SefirahConstants.BatteryAlerts.maxThreshold)
        XCTAssertTrue(loaded.clipboardReceive)
        XCTAssertTrue(loaded.notificationSync)
    }

    func testMissingDeviceFileReturnsDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sefirah-settings-\(UUID().uuidString)")
        let store = SettingsStore(directory: directory)
        let settings = try store.loadDevice(id: "unknown")
        XCTAssertEqual(settings.deviceId, "unknown")
        XCTAssertEqual(settings.frameRate, 60)
        XCTAssertEqual(settings.display, "0")
    }
}
