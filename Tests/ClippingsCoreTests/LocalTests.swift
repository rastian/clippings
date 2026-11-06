import XCTest
#if canImport(ClippingsCore)
@testable import ClippingsCore
#else
@testable import Clippings
#endif

@MainActor
final class LocalTests: XCTestCase {
    func makeStore() -> LocalStore { LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("test.sqlite")) }
    func testPersistenceAndRollback() async throws {
        let store = makeStore()
        try await store.transaction { $0.settings["name"] = "Original" }
        do { try await store.transaction { state in state.settings["name"] = "Lost"; throw ClippingsError.emptyName } } catch {}
        let reopened = LocalStore(url: store.url)
        let result = try await reopened.read()
        XCTAssertEqual(result.settings["name"], "Original")
    }
    func testTwoConnectionsDoNotLoseWrites() async throws {
        let first = makeStore(); let second = LocalStore(url: first.url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                let store = index.isMultiple(of: 2) ? first : second
                group.addTask { try await store.transaction { $0.settings["\(index)"] = "saved" } }
            }
            try await group.waitForAll()
        }
        let result = try await first.read()
        XCTAssertEqual(result.settings.count, 40)
    }
    func testCollectionsDuplicatePreventionSearchAndSorting() async throws {
        let store = makeStore(); let service = LibraryService(store: store)
        let library = try await service.createLibrary(name: "Family", userID: "A")
        let collection = try await service.createCollection(name: "Recipes", icon: "fork.knife", library: library, userID: "A")
        let first = try await service.saveLink(url: "https://example.com/a#top", title: "Pasta", collection: collection.id, library: library, userID: "A", now: Date(timeIntervalSince1970: 10))
        let duplicate = try await service.saveLink(url: "https://example.com/a", collection: collection.id, library: library, userID: "A")
        XCTAssertEqual(first.id, duplicate.id)
        let second = try await service.saveLink(url: "https://example.com/b", title: "Picnic", library: library, userID: "A", now: Date(timeIntervalSince1970: 20))
        try await service.saveNote(for: first, text: "Grandma’s favourite", userID: "A")
        var state = try await store.read()
        XCTAssertEqual(LinkRules.links(in: state, zone: library.zone).map(\.id), [second.id, first.id])
        XCTAssertEqual(LinkRules.links(in: state, zone: library.zone, oldestFirst: true).map(\.id), [first.id, second.id])
        for query in ["pasta", "RECIPES", "grandma", "example.com/a"] {
            XCTAssertEqual(LinkRules.links(in: state, zone: library.zone, query: query).map(\.id), [first.id])
        }
        try await service.delete(collection)
        state = try await store.read()
        XCTAssertEqual(state.items[first.key]?["collection"], "")
        XCTAssertEqual(state.visible(.link).count, 2)
        XCTAssertTrue(state.items[collection.key]?.deleted == true)
        XCTAssertFalse(state.pending.isEmpty)
        let note = try XCTUnwrap(state.visible(.note).first)
        XCTAssertEqual(note.zone.name, "clippings-personal")
    }
    func testReadOnlyAndMissingCollectionFailWithoutWrites() async throws {
        let store = makeStore(); let service = LibraryService(store: store)
        let library = try await service.createLibrary(name: "Family", userID: "A")
        do { _ = try await service.saveLink(url: "https://example.com", collection: "missing", library: library, userID: "A"); XCTFail("Must reject missing collection") } catch {}
        try await store.transaction { $0.zones[library.zone.key]?.canWrite = false }
        do { _ = try await service.saveLink(url: "https://example.com", library: library, userID: "A"); XCTFail("Must reject read-only write") } catch { XCTAssertEqual(error as? ClippingsError, .readOnly) }
        let result = try await store.read(); XCTAssertTrue(result.visible(.link).isEmpty)
    }
}
