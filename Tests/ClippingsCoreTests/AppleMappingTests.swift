#if !SWIFT_PACKAGE
import XCTest
import CloudKit
import UniformTypeIdentifiers
import LinkPresentation
@testable import Clippings

final class AppleMappingTests: XCTestCase {
    func testCloudRecordRoundTripAndSharedZoneMapping() throws {
        let owned = Zone(name: "clippings-family-test")
        let shared = Zone(name: owned.name, owner: "owner-ID", scope: .shared)
        let item = Item(id: "link", kind: .link, zone: owned, fields: ["title": Field("A recipe", clock: 3, actor: "device")])
        let record = CKRecord(recordType: RecordCodec.recordType, recordID: CKRecord.ID(recordName: item.id, zoneID: RecordCodec.zoneID(owned)))
        try RecordCodec.apply(item, to: record)
        let decoded = try RecordCodec.decode(record, zone: shared)
        XCTAssertEqual(decoded.zone, shared); XCTAssertEqual(decoded.title, item.title)
        XCTAssertEqual(decoded.fields, item.fields)
    }
    func testInvalidRecordAndFutureSchemaDoNotDecode() throws {
        let zone = Zone(name: "clippings-family-test")
        let record = CKRecord(recordType: RecordCodec.recordType, recordID: CKRecord.ID(recordName: "item", zoneID: RecordCodec.zoneID(zone)))
        XCTAssertThrowsError(try RecordCodec.decode(record, zone: zone))
        var future = Item(id: "item", kind: .link, zone: zone); future.schema = 99
        try RecordCodec.apply(future, to: record)
        XCTAssertThrowsError(try RecordCodec.decode(record, zone: zone))
    }
}
@MainActor
final class AppleSharingTests: XCTestCase {
    func testSharedZoneWithoutReferenceFetchesZoneWideShare() async throws {
        let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "clippings-family-test", ownerName: "owner-ID"))
        XCTAssertNil(zone.share)
        let share = CKShare(recordZoneID: zone.zoneID)
        let fetched = try await AppleCloudRepository.fetchShare(in: zone, scope: .shared) { id in
            XCTAssertEqual(id.zoneID, zone.zoneID)
            XCTAssertEqual(id.recordName, CKRecordNameZoneWideShare)
            return share
        }
        XCTAssertEqual(fetched?.recordID, share.recordID)
    }
    func testOwnerUsesStableAccountIDWithoutDiscoverableIdentity() {
        let shared = Zone(name: "clippings-family-test", owner: "owner-ID", scope: .shared)
        let share = CKShare(recordZoneID: RecordCodec.zoneID(shared))
        // Unsaved CloudKit shares have no server-resolved user identity. The zone
        // owner, not a display name or default-owner alias, addresses the mention.
        let members = AppleCloudRepository.members(in: share, zone: shared, currentUserID: "participant-ID")
        XCTAssertEqual(members.filter { $0.role == "Owner" }.map(\.id), ["owner-ID"])
        XCTAssertEqual(members.first?.name, "Library owner")
        let owned = Zone(name: shared.name)
        let ownerMembers = AppleCloudRepository.members(in: share, zone: owned, currentUserID: "owner-ID")
        XCTAssertEqual(ownerMembers.filter { $0.role == "Owner" }.map(\.id), ["owner-ID"])
    }
    func testMissingShareIsExpectedOnlyForAnUnsharedOwnedLibrary() async throws {
        let zone = CKRecordZone(zoneName: "clippings-family-test")
        let missing = try await AppleCloudRepository.fetchShare(in: zone, scope: .owned) { _ in throw CKError(.unknownItem) }
        XCTAssertNil(missing)
        do {
            _ = try await AppleCloudRepository.fetchShare(in: zone, scope: .shared) { _ in throw CKError(.unknownItem) }
            XCTFail("A missing participant share must not silently clear the member list")
        } catch { XCTAssertEqual((error as? CKError)?.code, .unknownItem) }
        do {
            _ = try await AppleCloudRepository.fetchShare(in: zone, scope: .owned) { _ in throw CKError(.networkUnavailable) }
            XCTFail("Network failures must be retried")
        } catch { XCTAssertEqual((error as? CKError)?.code, .networkUnavailable) }
    }
    func testInvalidShareRecordIsRejected() async throws {
        let zone = CKRecordZone(zoneName: "clippings-family-test")
        do {
            _ = try await AppleCloudRepository.fetchShare(in: zone, scope: .shared) { id in CKRecord(recordType: "Other", recordID: id) }
            XCTFail("A normal record cannot supply sharing permissions")
        } catch { XCTAssertEqual(error as? ClippingsError, .cloud("The family sharing information could not be read.")) }
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
