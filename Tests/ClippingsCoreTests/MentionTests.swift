import XCTest
#if canImport(ClippingsCore)
@testable import ClippingsCore
#else
@testable import Clippings
#endif

actor NotificationDouble: MentionNotifying {
    var ids: Set<String> = []
    var allowed = true
    var fail = false
    var calls = 0
    func schedule(id: String, linkKey: String) throws -> Bool {
        if fail { throw ClippingsError.cloud("Notification error") }
        if !allowed { return false }
        ids.insert(id); calls += 1; return true
    }
    func remove(ids: [String]) { self.ids.subtract(ids) }
    func setAllowed(_ value: Bool) { allowed = value }
    func setFailure(_ value: Bool) { fail = value }
    func scheduled() -> Set<String> { ids }
    func callCount() -> Int { calls }
}

@MainActor
final class MentionTests: XCTestCase {
    func fixture() async throws -> (LocalStore, LibraryService, Item, Item) {
        let store = LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mentions.sqlite"))
        let service = LibraryService(store: store)
        let library = try await service.createLibrary(name: "Family", userID: "A")
        try await store.transaction { $0.zones[library.zone.key]?.members = [Member(id: "A", name: "Same Name", role: "Owner", canWrite: true), Member(id: "B", name: "Same Name", role: "Member", canWrite: false)] }
        let link = try await service.saveLink(url: "https://example.com", library: library, userID: "A", recipients: ["A", "B", "unknown"])
        let state = try await store.read()
        let mention = try XCTUnwrap(state.visible(.mention).first)
        return (store, service, link, mention)
    }
    func testOnlyRecipientIsNotifiedAndNotificationsDeduplicate() async throws {
        let (store, _, _, mention) = try await fixture()
        let notifier = NotificationDouble(), processor = MentionProcessor(store: store, notifier: NotificationDouble())
        try await processor.process(userID: "A")
        let state = try await store.read(); XCTAssertEqual(state.visible(.mention).count, 1)
        XCTAssertTrue(state.notified.isEmpty)
        let recipient = MentionProcessor(store: store, notifier: notifier)
        try await recipient.process(userID: "B"); try await recipient.process(userID: "B")
        let scheduled = await notifier.scheduled(); let count = await notifier.callCount()
        XCTAssertEqual(scheduled, [mention.key]); XCTAssertEqual(count, 1)
    }
    func testPrivateReadReceiptWorksForReadOnlyParticipant() async throws {
        let (store, service, _, mention) = try await fixture()
        try await store.transaction { $0.zones[mention.zone.key]?.canWrite = false }
        try await service.markRead(mention, userID: "B")
        let state = try await store.read()
        XCTAssertTrue(LinkRules.unreadMentions(in: state, userID: "B").isEmpty)
        XCTAssertEqual(state.visible(.receipt).first?.zone.name, "clippings-personal")
        XCTAssertEqual(state.items[mention.key]?["read"], "false")
        do { try await service.markRead(mention, userID: "A"); XCTFail("Wrong recipient") } catch { XCTAssertEqual(error as? ClippingsError, .readOnly) }
    }
    func testPermissionDenialAndSchedulingFailurePreserveUnread() async throws {
        let (store, _, _, _) = try await fixture()
        let notifier = NotificationDouble(), processor = MentionProcessor(store: store, notifier: notifier)
        await notifier.setAllowed(false); try await processor.process(userID: "B")
        var state = try await store.read(); XCTAssertTrue(state.notified.isEmpty); XCTAssertEqual(LinkRules.unreadMentions(in: state, userID: "B").count, 1)
        await notifier.setAllowed(true); await notifier.setFailure(true)
        do { try await processor.process(userID: "B"); XCTFail("Expected scheduling error") } catch {}
        state = try await store.read(); XCTAssertTrue(state.notified.isEmpty)
        await notifier.setFailure(false); try await processor.process(userID: "B")
        state = try await store.read(); XCTAssertEqual(state.notified.count, 1)
    }
    func testDeletedLinksAndReadMentionsRemoveAlerts() async throws {
        let (store, service, link, _) = try await fixture()
        let notifier = NotificationDouble(), processor = MentionProcessor(store: store, notifier: notifier)
        try await processor.process(userID: "B")
        try await service.delete(link)
        try await processor.process(userID: "B")
        let scheduled = await notifier.scheduled(); XCTAssertTrue(scheduled.isEmpty)
    }
    func testOrdinarySavesAndEditsStaySilent() async throws {
        var state = Snapshot(); let zone = Zone(name: "family")
        let link = state.edit(Item(kind: .link, zone: zone), values: ["title": "Recipe", "author": "A"])
        XCTAssertFalse(LinkRules.shouldNotify(link, userID: "B", notified: []))
        let collection = state.edit(Item(kind: .collection, zone: zone), values: ["title": "Recipes"])
        XCTAssertFalse(LinkRules.shouldNotify(collection, userID: "B", notified: []))
    }
    func testMentioningExistingLinkPreservesItAndDeduplicatesRecipients() async throws {
        let (store, service, link, _) = try await fixture()
        try await store.transaction { state in
            state.zones[link.zone.key]?.members[1].canWrite = true
            state.zones[link.zone.key]?.members.append(Member(id: "C", name: "Someone else", role: "Member", canWrite: true))
            state.pending = [:]
        }
        // B mentions the owner and another member on A’s link, without resaving it.
        try await service.mention(link, recipients: ["A", "B", "C", "unknown"], userID: "B")
        let first = try await store.read()
        try await service.mention(link, recipients: ["A", "C"], userID: "B")
        let retried = try await store.read()
        XCTAssertEqual(retried.items[link.key], link)
        XCTAssertEqual(retried.visible(.mention).count, 3)
        XCTAssertEqual(Set(retried.pending.values.map { $0["recipient"] }), ["A", "C"])
        XCTAssertTrue(retried.pending.values.allSatisfy { $0.kind == .mention && $0["author"] == "B" })
        XCTAssertEqual(retried.pending, first.pending)
    }
    func testMentioningRequiresAnAvailableWritableLink() async throws {
        let (store, service, link, _) = try await fixture()
        let original = try await store.read()
        try await store.transaction { $0.zones[link.zone.key]?.canWrite = false }
        do { try await service.mention(link, recipients: ["A"], userID: "B"); XCTFail("View-only participant wrote a mention") }
        catch { XCTAssertEqual(error as? ClippingsError, .readOnly) }
        try await store.transaction { state in
            state.zones[link.zone.key]?.canWrite = true
            state.zones[link.zone.key]?.available = false
        }
        do { try await service.mention(link, recipients: ["A"], userID: "B"); XCTFail("Revoked participant wrote a mention") }
        catch { XCTAssertEqual(error as? ClippingsError, .readOnly) }
        try await store.transaction { state in
            state.zones[link.zone.key]?.available = true
            state.items[link.key]?.deleted = true
        }
        do { try await service.mention(link, recipients: ["A"], userID: "B"); XCTFail("Mentioned a deleted link") }
        catch { XCTAssertEqual(error as? ClippingsError, .storage("This link is no longer available.")) }
        let state = try await store.read()
        XCTAssertEqual(state.visible(.mention), original.visible(.mention))
        XCTAssertEqual(state.pending, original.pending)
    }
}
