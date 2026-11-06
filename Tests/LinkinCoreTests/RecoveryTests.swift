import XCTest
#if canImport(LinkinCore)
@testable import LinkinCore
#else
@testable import linkin
#endif

actor PagedCloudDouble: CloudRepository {
    let zone = Zone(name: "linkin-family-paged")
    var failLastPage = true
    func currentUserID() -> String { "A" }
    func listZones() -> [ZoneState] { [ZoneState(zone: zone)] }
    func createZone(_ zone: Zone) {}
    func changes(in zone: Zone, since token: Data?) throws -> ChangePage {
        if token == nil {
            let item = Item(id: "family", kind: .library, zone: zone, fields: ["title": Field("Family", clock: 1, actor: "a")])
            return ChangePage(items: [item], token: Data([1]), moreComing: true)
        }
        if token == Data([1]) {
            if failLastPage { throw LinkinError.cloud("Second page failed") }
            let item = Item(id: "link", kind: .link, zone: zone, fields: ["title": Field("Recipe", clock: 2, actor: "a")])
            return ChangePage(items: [item], token: Data([2]))
        }
        return ChangePage(items: [], token: Data([2]))
    }
    func save(_ item: Item, wasUploaded: Bool) -> Item { item }
    func remove(_ zone: Zone) {}
    func succeed() { failLastPage = false }
}

@MainActor
final class RecoveryTests: XCTestCase {
    func store() -> LocalStore { LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("recovery.sqlite")) }
    func testFailedPageDoesNotAdvanceTokenOrCommitPartialFetch() async throws {
        let store = store(), cloud = PagedCloudDouble()
        let engine = SyncEngine(store: store, cloud: cloud)
        do { try await engine.synchronize(); XCTFail("Second page should fail") } catch {}
        var state = try await store.read()
        XCTAssertTrue(state.items.isEmpty); XCTAssertNil(state.zones.values.first?.token)
        await cloud.succeed(); try await engine.synchronize()
        state = try await store.read(); XCTAssertEqual(state.items.count, 2)
        XCTAssertEqual(state.zones.values.first?.token, Data([2]))
    }
    func testMovingAndLongTextValidationAreAtomic() async throws {
        let store = store(), service = LibraryService(store: store)
        let family = try await service.createLibrary(name: "Family", userID: "A")
        let collection = try await service.createCollection(name: "Places", icon: "map", library: family, userID: "A")
        let link = try await service.saveLink(url: "https://example.com", library: family, userID: "A", operationID: "operation")
        try await service.update(link, values: ["collection": collection.id])
        _ = try await service.saveLink(url: "https://example.com", library: family, userID: "A", operationID: "operation")
        var state = try await store.read(); XCTAssertEqual(state.items[link.key]?["collection"], collection.id)
        do { try await service.update(link, values: ["collection": "missing"]); XCTFail("Invalid collection") } catch {}
        do { try await service.saveNote(for: link, text: String(repeating: "x", count: 10_001), userID: "A"); XCTFail("Must not silently truncate") } catch {}
        state = try await store.read(); XCTAssertTrue(state.visible(.note).isEmpty)
        XCTAssertEqual(state.items[link.key]?["collection"], collection.id)
        XCTAssertThrowsError(try LinkRules.name(String(repeating: "x", count: 121)))
    }
    func testSearchWithManyLinksAndPrivateNotes() {
        var state = Snapshot(); let zone = Zone(name: "family")
        for index in 0..<2_000 {
            let link = Item(id: "link-\(index)", kind: .link, zone: zone, fields: ["title": Field("Recipe \(index)", clock: 1, actor: "a"), "url": Field("https://example.com/\(index)", clock: 1, actor: "a")])
            state.items[link.key] = link
            let note = Item(id: "note-\(index)", kind: .note, zone: Zone(name: "linkin-personal"), fields: ["link": Field(link.key, clock: 1, actor: "a"), "text": Field(index == 1_999 ? "Grandma’s favourite" : "A note", clock: 1, actor: "a")])
            state.items[note.key] = note
        }
        XCTAssertEqual(LinkRules.links(in: state, zone: zone, query: "grandma").map(\.id), ["link-1999"])
        measure { _ = LinkRules.links(in: state, zone: zone, query: "recipe") }
    }
}
