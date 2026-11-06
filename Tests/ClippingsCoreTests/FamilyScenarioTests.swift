import XCTest
#if canImport(ClippingsCore)
@testable import ClippingsCore
#else
@testable import Clippings
#endif

/// Models owner/private and participant/shared projections. This is not a CloudKit service test.
actor FamilyServerDouble {
    struct Library: Sendable { var owner: String; var name: String; var members: [String: Bool] }
    var libraries: [String: Library] = [:]
    var records: [String: Item] = [:]
    func zoneKey(_ zone: Zone, user: String) -> String { "\(zone.scope == .owned ? user : zone.owner)|\(zone.name)" }
    func create(_ zone: Zone, user: String) {
        let key = zoneKey(zone, user: user)
        if libraries[key] == nil { libraries[key] = Library(owner: user, name: zone.name, members: [user: true]) }
    }
    func accept(zone: Zone, owner: String, participant: String) throws {
        let key = "\(owner)|\(zone.name)"
        guard libraries[key] != nil else { throw ClippingsError.missingLibrary }
        libraries[key]?.members[participant] = true
    }
    func zones(user: String) -> [ZoneState] {
        libraries.values.filter { $0.members[user] != nil }.map { library in
            let zone = Zone(name: library.name, owner: library.owner == user ? "__defaultOwner__" : library.owner, scope: library.owner == user ? .owned : .shared)
            var state = ZoneState(zone: zone)
            state.members = library.members.map { Member(id: $0.key, name: $0.key, role: $0.key == library.owner ? "Owner" : "Member", canWrite: $0.value) }
            state.canWrite = library.members[user] == true
            return state
        }
    }
    func fetch(_ zone: Zone, user: String) throws -> ChangePage {
        let key = zoneKey(zone, user: user)
        guard libraries[key]?.members[user] != nil else { throw ClippingsError.readOnly }
        let found = records.filter { $0.key.hasPrefix(key + "|") }.map { _, item in var item = item; item.zone = zone; return item }
        return ChangePage(items: found, token: Data([1]))
    }
    func save(_ item: Item, user: String) throws -> Item {
        let zoneKey = zoneKey(item.zone, user: user)
        guard libraries[zoneKey]?.members[user] == true else { throw ClippingsError.readOnly }
        let key = zoneKey + "|" + item.id
        var result = try records[key]?.merging(item) ?? item
        records[key] = result; result.zone = item.zone; return result
    }
    func remove(_ zone: Zone, user: String) {
        let key = zoneKey(zone, user: user)
        if libraries[key]?.owner == user { libraries.removeValue(forKey: key) }
        else { libraries[key]?.members.removeValue(forKey: user) }
    }
}
struct FamilyClientDouble: CloudRepository {
    let server: FamilyServerDouble
    let user: String
    func currentUserID() async -> String { user }
    func listZones() async -> [ZoneState] { await server.zones(user: user) }
    func createZone(_ zone: Zone) async { await server.create(zone, user: user) }
    func changes(in zone: Zone, since token: Data?) async throws -> ChangePage { try await server.fetch(zone, user: user) }
    func save(_ item: Item, wasUploaded: Bool) async throws -> Item { try await server.save(item, user: user) }
    func remove(_ zone: Zone) async { await server.remove(zone, user: user) }
}

@MainActor
final class FamilyScenarioTests: XCTestCase {
    func store() -> LocalStore { LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("family.sqlite")) }
    func testInvitedMemberMentionsOwnerOnOwnersExistingLink() async throws {
        let server = FamilyServerDouble(), a = store(), b = store()
        let engineA = SyncEngine(store: a, cloud: FamilyClientDouble(server: server, user: "A"))
        let engineB = SyncEngine(store: b, cloud: FamilyClientDouble(server: server, user: "B"))
        let serviceA = LibraryService(store: a), serviceB = LibraryService(store: b)
        let family = try await serviceA.createLibrary(name: "Family", userID: "A")
        let link = try await serviceA.saveLink(url: "https://example.com/recipe", title: "Pasta", library: family, userID: "A")
        try await engineA.synchronize()
        try await server.accept(zone: family.zone, owner: "A", participant: "B")
        try await engineB.synchronize()
        let stateB = try await b.read()
        let sharedLink = try XCTUnwrap(stateB.visible(.link).first)
        XCTAssertEqual(sharedLink.zone.scope, .shared)
        try await serviceB.mention(sharedLink, recipients: ["A"], userID: "B")
        try await engineB.synchronize(); try await engineA.synchronize()
        let stateA = try await a.read()
        let mention = try XCTUnwrap(LinkRules.unreadMentions(in: stateA, userID: "A").first)
        XCTAssertEqual(mention["author"], "B")
        XCTAssertEqual(mention["link"], link.id)
        XCTAssertEqual(stateA.items[link.key], link)
        let notifier = NotificationDouble()
        let ownerProcessor = MentionProcessor(store: a, notifier: notifier)
        try await ownerProcessor.process(userID: "A"); try await ownerProcessor.process(userID: "A")
        let delivered = await notifier.scheduled(), calls = await notifier.callCount()
        XCTAssertEqual(delivered, [mention.key]); XCTAssertEqual(calls, 1)
        XCTAssertTrue(LinkRules.unreadMentions(in: stateA, userID: "B").isEmpty)
    }
    func testTwoAccountFamilyScenarioWithPrivateNotesAndReadReceipts() async throws {
        let server = FamilyServerDouble(), a = store(), b = store(), secondB = store()
        let engineA = SyncEngine(store: a, cloud: FamilyClientDouble(server: server, user: "A"))
        let engineB = SyncEngine(store: b, cloud: FamilyClientDouble(server: server, user: "B"))
        let engineSecondB = SyncEngine(store: secondB, cloud: FamilyClientDouble(server: server, user: "B"))
        let serviceA = LibraryService(store: a), serviceB = LibraryService(store: b)
        let family = try await serviceA.createLibrary(name: "Our family", userID: "A")
        let collection = try await serviceA.createCollection(name: "Recipes", icon: "fork.knife", library: family, userID: "A")
        let first = try await serviceA.saveLink(url: "https://example.com/recipe", title: "Pasta", collection: collection.id, library: family, userID: "A")
        try await engineA.synchronize()
        try await server.accept(zone: family.zone, owner: "A", participant: "B")
        try await engineB.synchronize()
        var stateB = try await b.read()
        let joined = try XCTUnwrap(stateB.libraries.first)
        XCTAssertEqual(joined.zone.scope, .shared)
        XCTAssertEqual(stateB.visible(.collection).first?.title, "Recipes")
        XCTAssertEqual(stateB.visible(.link).first?.title, "Pasta")
        _ = try await serviceB.saveLink(url: "https://example.com/trip", title: "A weekend away", library: joined, userID: "B")
        try await engineB.synchronize(); try await engineA.synchronize()
        var stateA = try await a.read(); XCTAssertEqual(stateA.visible(.link).count, 2)
        _ = try await serviceA.saveLink(url: first["url"], collection: collection.id, library: family, userID: "A", recipients: ["B"])
        try await engineA.synchronize(); try await engineB.synchronize()
        stateB = try await b.read()
        let mention = try XCTUnwrap(LinkRules.unreadMentions(in: stateB, userID: "B").first)
        let notifier = NotificationDouble(); let processor = MentionProcessor(store: b, notifier: notifier)
        try await processor.process(userID: "B")
        let delivered = await notifier.scheduled(); XCTAssertEqual(delivered, [mention.key])
        try await serviceB.markRead(mention, userID: "B")
        let bLink = try XCTUnwrap(stateB.visible(.link).first { $0.id == first.id })
        try await serviceB.saveNote(for: bLink, text: "A private idea", userID: "B")
        try await engineB.synchronize(); try await engineSecondB.synchronize(); try await engineA.synchronize()
        let anotherB = try await secondB.read()
        XCTAssertTrue(LinkRules.unreadMentions(in: anotherB, userID: "B").isEmpty)
        XCTAssertEqual(anotherB.visible(.note).first?["text"], "A private idea")
        stateA = try await a.read()
        XCTAssertTrue(stateA.visible(.note).isEmpty); XCTAssertTrue(stateA.visible(.receipt).isEmpty)
        XCTAssertEqual(Set(stateA.visible(.link).map(\.id)), Set(anotherB.visible(.link).map(\.id)))
        try await processor.process(userID: "B")
        let remainingAlerts = await notifier.scheduled(); XCTAssertTrue(remainingAlerts.isEmpty)
        try await serviceB.delete(bLink); try await engineB.synchronize(); try await engineA.synchronize()
        stateA = try await a.read(); XCTAssertTrue(stateA.items[first.key]?.deleted == true)
    }
}
