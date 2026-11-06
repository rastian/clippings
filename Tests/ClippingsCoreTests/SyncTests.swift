import XCTest
#if canImport(ClippingsCore)
@testable import ClippingsCore
#else
@testable import Clippings
#endif

actor CloudDouble: CloudRepository {
    var user: String
    var storage: [String: Item] = [:]
    var zones: [ZoneState] = []
    var failWrites = false
    var expireOnce = false
    var saves = 0
    var changeAccountOnFetch = false
    func changeAccountDuringFetch() { changeAccountOnFetch = true }
    init(user: String = "A") { self.user = user }
    func currentUserID() -> String { user }
    func setUser(_ value: String) { user = value }
    func setFail(_ value: Bool) { failWrites = value }
    func expire() { expireOnce = true }
    func listZones() -> [ZoneState] { zones }
    func createZone(_ zone: Zone) { if !zones.contains(where: { $0.zone == zone }) { zones.append(ZoneState(zone: zone)) } }
    func changes(in zone: Zone, since token: Data?) throws -> ChangePage {
        if changeAccountOnFetch { user = "B"; changeAccountOnFetch = false }
        if expireOnce && token != nil { expireOnce = false; throw SyncFailure.expiredToken }
        return ChangePage(items: storage.values.filter { $0.zone == zone }, token: Data([1]))
    }
    func save(_ item: Item, wasUploaded: Bool) throws -> Item {
        if failWrites { throw ClippingsError.cloud("Offline") }
        if wasUploaded && storage[item.key] == nil { throw SyncFailure.removedRecord }
        let saved = try storage[item.key]?.merging(item) ?? item
        storage[item.key] = saved; saves += 1
        return saved
    }
    func remove(_ zone: Zone) { zones.removeAll { $0.zone == zone }; storage = storage.filter { $0.value.zone != zone } }
    func eraseRecord(_ item: Item) { storage.removeValue(forKey: item.key) }
    func insert(_ item: Item) { storage[item.key] = item }
    func all() -> [Item] { Array(storage.values) }
}

@MainActor
final class SyncTests: XCTestCase {
    func store() -> LocalStore { LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("sync.sqlite")) }
    func testOfflineRetryDoesNotDuplicateAndBindsLocalIdentity() async throws {
        let store = store(); let service = LibraryService(store: store); let cloud = CloudDouble()
        let engine = SyncEngine(store: store, cloud: cloud)
        let library = try await service.createLibrary(name: "Our family", userID: "local-user")
        let link = try await service.saveLink(url: "https://example.com", library: library, userID: "local-user")
        await cloud.setFail(true)
        do { try await engine.synchronize(); XCTFail("Offline write must fail") } catch {}
        let pending = try await store.read(); XCTAssertEqual(pending.pending.count, 2)
        await cloud.setFail(false); try await engine.synchronize(); try await engine.synchronize()
        let state = try await store.read(); let remote = await cloud.all()
        XCTAssertTrue(state.pending.isEmpty); XCTAssertEqual(remote.count, 2)
        XCTAssertEqual(state.items[link.key]?["author"], "A")
    }
    func testTokenExpiryKeepsUnsentWorkAndRecoversHardDeletion() async throws {
        let store = store(); let service = LibraryService(store: store); let cloud = CloudDouble()
        let engine = SyncEngine(store: store, cloud: cloud)
        let library = try await service.createLibrary(name: "Family", userID: "A")
        let link = try await service.saveLink(url: "https://example.com", title: "Original", library: library, userID: "A")
        try await engine.synchronize()
        try await service.update(link, values: ["title": "Offline edit"])
        await cloud.eraseRecord(link); await cloud.expire(); try await engine.synchronize()
        let state = try await store.read()
        XCTAssertTrue(state.items[link.key]?.deleted == true)
        XCTAssertEqual(state.recovered?[link.key]?.title, "Offline edit")
        XCTAssertNil(state.pending[link.key])
    }
    func testRemovedZoneIsNotRecreatedAndPendingWorkSurvives() async throws {
        let store = store(); let service = LibraryService(store: store); let cloud = CloudDouble()
        let engine = SyncEngine(store: store, cloud: cloud)
        let library = try await service.createLibrary(name: "Family", userID: "A")
        try await engine.synchronize()
        let link = try await service.saveLink(url: "https://example.com", library: library, userID: "A")
        await cloud.remove(library.zone); try await engine.synchronize()
        let state = try await store.read(); let zones = await cloud.listZones()
        XCTAssertTrue(zones.isEmpty); XCTAssertFalse(state.zones[library.zone.key]?.available ?? true)
        XCTAssertNotNil(state.pending[link.key])
    }
    func testAccountSwitchDoesNotUploadToAnotherAccount() async throws {
        let store = store(); let service = LibraryService(store: store); let cloud = CloudDouble()
        let engine = SyncEngine(store: store, cloud: cloud)
        _ = try await service.createLibrary(name: "Family", userID: "A"); try await engine.synchronize()
        await cloud.setUser("B")
        do { try await engine.synchronize(); XCTFail("Must isolate accounts") } catch { XCTAssertEqual(error as? ClippingsError, .accountChanged) }
        let state = try await store.read(); XCTAssertEqual(state.accountID, "A")
    }
    func testTwoDevicesConvergeAfterIndependentEdits() async throws {
        let first = store(), second = store(), cloud = CloudDouble()
        let a = SyncEngine(store: first, cloud: cloud), b = SyncEngine(store: second, cloud: cloud)
        let serviceA = LibraryService(store: first), serviceB = LibraryService(store: second)
        let library = try await serviceA.createLibrary(name: "Family", userID: "A")
        let link = try await serviceA.saveLink(url: "https://example.com", title: "Original", library: library, userID: "A")
        try await a.synchronize(); try await b.synchronize()
        try await serviceA.update(link, values: ["title": "New title"])
        try await serviceB.update(link, values: ["summary": "New description"])
        try await b.synchronize(); try await a.synchronize(); try await b.synchronize()
        let stateA = try await first.read(), stateB = try await second.read()
        XCTAssertEqual(stateA.items[link.key], stateB.items[link.key])
        XCTAssertEqual(stateA.items[link.key]?.title, "New title")
        XCTAssertEqual(stateA.items[link.key]?["summary"], "New description")
    }
    func testAccountChangeDuringSyncPreservesOutbox() async throws {
        let store = store(); let service = LibraryService(store: store); let cloud = CloudDouble()
        let engine = SyncEngine(store: store, cloud: cloud)
        _ = try await service.createLibrary(name: "Family", userID: "A")
        await cloud.changeAccountDuringFetch()
        do { try await engine.synchronize(); XCTFail("Must stop before uploading under a changed identity") }
        catch { XCTAssertEqual(error as? ClippingsError, .accountChanged) }
        let remote = await cloud.all(), state = try await store.read()
        XCTAssertTrue(remote.isEmpty); XCTAssertEqual(state.pending.count, 1)
    }

}
