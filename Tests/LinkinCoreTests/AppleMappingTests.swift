#if !SWIFT_PACKAGE
import XCTest
import CloudKit
import UniformTypeIdentifiers
import LinkPresentation
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
@MainActor
final class AttachmentReaderTests: XCTestCase {
    func testNativeURLProvider() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/recipe"))
        let provider = NSItemProvider(object: url as NSURL)
        let value = await AttachmentReader.text(from: provider, type: UTType.url.identifier)
        XCTAssertEqual(value, url.absoluteString)
    }
    func testNativeTextProvider() async throws {
        let provider = NSItemProvider(object: "See https://example.com/video" as NSString)
        let value = await AttachmentReader.text(from: provider, type: UTType.plainText.identifier)
        XCTAssertEqual(try SharedInput.url(in: value ?? "").path, "/video")
    }
}

@MainActor
private final class UnavailableMetadata: MetadataProviding {
    let requested: XCTestExpectation
    init(requested: XCTestExpectation) { self.requested = requested }
    func metadata(for url: URL) async throws -> LPLinkMetadata {
        requested.fulfill()
        throw URLError(.timedOut)
    }
}
@MainActor
final class MetadataIntegrationTests: XCTestCase {
    func testMetadataFailureCannotPreventSaving() async throws {
        let store = LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("metadata.sqlite"))
        let requested = XCTestExpectation(description: "Metadata requested after saving")
        let model = AppModel(store: store, metadata: UnavailableMetadata(requested: requested))
        let created = await model.createLibrary("Family")
        XCTAssertTrue(created)
        let saved = await model.addLink(url: "https://example.com", title: "", collection: nil)
        XCTAssertTrue(saved)
        let result = await XCTWaiter.fulfillment(of: [requested], timeout: 3)
        XCTAssertEqual(result, .completed)
        let state = try await store.read()
        XCTAssertEqual(state.visible(.link).count, 1)
        XCTAssertEqual(state.visible(.link).first?.title, "example.com")
        XCTAssertNil(model.error)
    }
}

#endif
