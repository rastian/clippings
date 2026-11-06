import XCTest
#if canImport(LinkinCore)
@testable import LinkinCore
#else
@testable import linkin
#endif

final class DomainTests: XCTestCase {
    func testURLValidation() throws {
        XCTAssertEqual(try LinkRules.canonical("https://EXAMPLE.com:443#hello"), "https://example.com/")
        for input in ["", "javascript:alert(1)", "file:///tmp/secret", "https://user:pass@example.com", "https://", "not a url"] {
            XCTAssertThrowsError(try LinkRules.validatedURL(input))
        }
        XCTAssertEqual(try LinkRules.validatedURL(" https://example.com/a?q=1 ").host, "example.com")
    }
    func testMetadataFallbackAndValidation() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertEqual(LinkRules.metadataTitle("  ", url: url), "example.com")
        XCTAssertEqual(LinkRules.metadataTitle(" Recipe ", url: url), "Recipe")
        XCTAssertThrowsError(try LinkRules.name(" \n"))
    }
    func testMergeIsCommutativeAndDeletionWins() throws {
        let zone = Zone(name: "family")
        var a = Item(id: "1", kind: .link, zone: zone, fields: ["title": Field("A", clock: 1, actor: "a")])
        let b = Item(id: "1", kind: .link, zone: zone, fields: ["title": Field("B", clock: 1, actor: "b"), "url": Field("https://example.com", clock: 1, actor: "b")])
        XCTAssertEqual(try a.merging(b), try b.merging(a))
        XCTAssertEqual(try a.merging(b).title, "B")
        a.deleted = true
        XCTAssertTrue(try b.merging(a).deleted)
    }
    func testConcurrentEditStaysQueued() throws {
        var state = Snapshot()
        let item = Item(kind: .link, zone: Zone(name: "family"))
        let sent = state.edit(item, values: ["title": "Before"])
        let later = state.edit(item, values: ["title": "After"])
        try state.acknowledge(sent, saved: sent)
        XCTAssertEqual(state.pending[item.key], later)
        try state.acknowledge(later, saved: later)
        XCTAssertTrue(state.pending.isEmpty)
    }
    func testUnsupportedSchemaFailsWithoutDiscarding() throws {
        var state = Snapshot()
        var item = Item(kind: .library, zone: Zone(name: "family")); item.schema = 99
        XCTAssertThrowsError(try state.receive(item))
        XCTAssertTrue(state.items.isEmpty)
    }
    func testLosingConcurrentEditIsRecoverable() throws {
        var state = Snapshot(); state.actor = "a"
        let item = Item(id: "conflict", kind: .link, zone: Zone(name: "family"))
        let queued = state.edit(item, values: ["title": "My title"])
        var remote = queued
        remote.fields["title"] = Field("Their title", clock: queued.revision, actor: "z")
        try state.receive(remote)
        XCTAssertEqual(state.items[item.key]?.title, "Their title")
        XCTAssertEqual(state.recovered?[item.key]?.title, "My title")
    }

    func testSharedURLAndCaptionInputs() throws {
        XCTAssertEqual(try SharedInput.url(in: "Look at this recipe https://example.com/recipe #family").host, "example.com")
        XCTAssertEqual(try SharedInput.url(in: "https://example.com/video").path, "/video")
        XCTAssertThrowsError(try SharedInput.url(in: "Just a photo caption"))
        XCTAssertThrowsError(try SharedInput.url(in: "file:///private/secret"))
        XCTAssertThrowsError(try SharedInput.url(in: String(repeating: "a", count: 40_000)))
    }

    func testInvitationContainerAndAccountValidation() throws {
        XCTAssertNoThrow(try InvitationRules.validate(container: "iCloud.linkin", expected: "iCloud.linkin", currentUser: "A", boundUser: "A"))
        XCTAssertThrowsError(try InvitationRules.validate(container: "iCloud.other", expected: "iCloud.linkin", currentUser: "A", boundUser: nil))
        XCTAssertThrowsError(try InvitationRules.validate(container: "iCloud.linkin", expected: "iCloud.linkin", currentUser: "B", boundUser: "A"))
        XCTAssertThrowsError(try InvitationRules.validate(container: "iCloud.linkin", expected: "iCloud.linkin", currentUser: "", boundUser: nil))
    }

}
