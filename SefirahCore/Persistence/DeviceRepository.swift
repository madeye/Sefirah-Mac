import Foundation
import GRDB

public struct DeviceRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(database: AppDatabase) {
        dbQueue = database.dbQueue
    }

    public func fetchLocalDevice() throws -> LocalDeviceRecord? {
        try dbQueue.read { db in
            try LocalDeviceRecord.fetchOne(db)
        }
    }

    @discardableResult
    public func ensureLocalDevice(name: String) throws -> LocalDeviceRecord {
        if let existing = try fetchLocalDevice() {
            if existing.deviceName == name { return existing }
            var updated = existing
            updated.deviceName = name
            try dbQueue.write { db in
                try updated.update(db)
            }
            return updated
        }
        let created = LocalDeviceRecord(deviceId: UUID().uuidString, deviceName: name)
        try dbQueue.write { db in
            try created.insert(db)
        }
        return created
    }

    public func fetchPairedDevices() throws -> [PairedDeviceRecord] {
        try dbQueue.read { db in
            try PairedDeviceRecord.fetchAll(db)
        }
    }

    public func fetchPairedDevice(id: String) throws -> PairedDeviceRecord? {
        try dbQueue.read { db in
            try PairedDeviceRecord.fetchOne(db, key: id)
        }
    }

    public func upsertPairedDevice(_ device: PairedDeviceRecord) throws {
        try dbQueue.write { db in
            try device.save(db)
        }
    }

    public func deletePairedDevice(id: String) throws {
        try dbQueue.write { db in
            _ = try PairedDeviceRecord.deleteOne(db, key: id)
        }
    }
}
