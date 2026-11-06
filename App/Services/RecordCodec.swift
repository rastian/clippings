import CloudKit
import Foundation

enum RecordCodec {
    static let recordType = "LinkinItem"
    static func decode(_ record: CKRecord, zone: Zone) throws -> Item {
        guard record.recordType == recordType, let data = record["payload"] as? Data else { throw LinkinError.storage("An iCloud record could not be read.") }
        var item = try JSONDecoder().decode(Item.self, from: data)
        guard item.schema <= Item.schemaVersion, item.id == record.recordID.recordName else { throw LinkinError.incompatibleSchema }
        item.zone = zone
        return item
    }
    static func apply(_ item: Item, to record: CKRecord) throws {
        let payload = try JSONEncoder().encode(item)
        guard payload.count < 900_000 else { throw LinkinError.storage("This item is too large to sync. Shorten its notes or description.") }
        record["payload"] = payload as CKRecordValue
        record["kind"] = item.kind.rawValue as CKRecordValue
        record["schemaVersion"] = item.schema as CKRecordValue
    }
    static func zoneID(_ zone: Zone) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zone.name, ownerName: zone.scope == .owned ? CKCurrentUserDefaultName : zone.owner)
    }
    static func tokenData(_ token: CKServerChangeToken) throws -> Data { try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) }
    static func token(_ data: Data?) throws -> CKServerChangeToken? {
        guard let data else { return nil }
        guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) else { throw SyncFailure.expiredToken }
        return token
    }
}
