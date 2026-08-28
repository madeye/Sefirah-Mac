import Foundation

public enum SefirahConstants {
    public static let schemaVersion = 5
    public static let databaseFileName = "sefirah.db"
    public static let certificateFileName = "Sefirah.cer"
    public static let privateKeyFileName = "Sefirah.key"
    public static let certificateCommonName = "SefirahCastle"

    public enum BatteryAlerts {
        public static let defaultThreshold = 20
        public static let minThreshold = 5
        public static let maxThreshold = 50
    }

    public enum Ports {
        public static let discovery = 5149
        public static let controlRange = 5150...5169
        public static let transferRange = 5152...5169
    }

    public static var defaultDownloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    public static var defaultRemoteStorageDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("RemoteDevices")
    }
}
