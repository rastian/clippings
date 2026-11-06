#if !SWIFT_PACKAGE
import XCTest
import CloudKit
@testable import linkin

final class AppleMappingTests: XCTestCase {
    func testCloudRecordRoundTripAndSharedZoneMapping() throws {
        let owned = Zone(name: "linkin-family-test")
        let shared = Zone(name: owned.name, owner: "owner-ID", scope: .shared)
        let item = Item(id: "link", kind: .link, zone: owned, fields: ["title": Field("A recipe", clock: 3, actor: "device")])
        let record = CKRecord(recordType: RecordCodec.recordType, recordID: CKRecord.ID(recordName: item.id, zoneID: RecordCodec.zoneID(owned)))
        try RecordCodec.apply(item, to: record)
        let decoded = try RecordCodec.decode(record, zone: shared)
        XCTAssertEqual(decoded.zone, shared); XCTAssertEqual(decoded.title, item.title)
        XCTAssertEqual(decoded.fields, item.fields)
    }
    func testInvalidRecordAndFutureSchemaDoNotDecode() throws {
        let zone = Zone(name: "linkin-family-test")
        let record = CKRecord(recordType: RecordCodec.recordType, recordID: CKRecord.ID(recordName: "item", zoneID: RecordCodec.zoneID(zone)))
        XCTAssertThrowsError(try RecordCodec.decode(record, zone: zone))
        var future = Item(id: "item", kind: .link, zone: zone); future.schema = 99
        try RecordCodec.apply(future, to: record)
        XCTAssertThrowsError(try RecordCodec.decode(record, zone: zone))
    }
}
#endif
