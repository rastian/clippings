#if !SWIFT_PACKAGE
import XCTest
import UserNotifications
@testable import Clippings

@MainActor
final class NotificationDeliveryTests: XCTestCase {
    func incomingOwnerMention() async throws -> (AppModel, LocalStore, NotificationDouble) {
        let server = FamilyServerDouble()
        let ownerStore = LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("owner.sqlite"))
        let memberStore = LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("member.sqlite"))
        let ownerEngine = SyncEngine(store: ownerStore, cloud: FamilyClientDouble(server: server, user: "owner"))
        let memberEngine = SyncEngine(store: memberStore, cloud: FamilyClientDouble(server: server, user: "member"))
        let service = LibraryService(store: ownerStore)
        let family = try await service.createLibrary(name: "Family", userID: "owner")
        try await ownerEngine.synchronize()
        try await server.accept(zone: family.zone, owner: "owner", participant: "member")
        try await ownerEngine.synchronize()
        _ = try await service.saveLink(url: "https://example.com/trip", library: family, userID: "owner", recipients: ["member"])
        try await ownerEngine.synchronize()
        let notifier = NotificationDouble()
        return (AppModel(store: memberStore, syncEngine: memberEngine, notifier: notifier), memberStore, notifier)
    }
    func testOwnerMentionProcessesOnBackgroundLaunchBeforeAnyScreenStarts() async throws {
        let (model, _, notifier) = try await incomingOwnerMention()
        XCTAssertFalse(model.loaded)
        // No start(), screen, or AppEvents callback is installed for this model.
        let changed = await model.refreshFromNotification()
        XCTAssertTrue(changed)
        XCTAssertTrue(model.loaded)
        let mention = try XCTUnwrap(model.unread.first)
        XCTAssertEqual(mention.zone.scope, .shared)
        XCTAssertEqual(mention["author"], "owner")
        XCTAssertEqual(mention["recipient"], "member")
        let delivered = await notifier.scheduled()
        XCTAssertEqual(delivered, [mention.key])
        let repeated = await model.refreshFromNotification()
        XCTAssertFalse(repeated)
        let count = await notifier.callCount()
        XCTAssertEqual(count, 1)
    }
    func testPermissionDenialKeepsMentionAvailableUntilAlertsAreEnabled() async throws {
        let (model, store, notifier) = try await incomingOwnerMention()
        await notifier.setAllowed(false)
        _ = await model.refreshFromNotification()
        XCTAssertEqual(model.unread.count, 1)
        let denied = try await store.read()
        XCTAssertTrue(denied.notified.isEmpty)
        await notifier.setAllowed(true)
        await model.refresh()
        let delivered = await notifier.scheduled()
        XCTAssertEqual(delivered, Set(model.unread.map(\.key)))
    }
    func testForegroundAlertsAreLimitedToExplicitMentions() {
        let content = UNMutableNotificationContent()
        content.userInfo = ["linkKey": "shared|owner|family|link"]
        XCTAssertTrue(MentionNotificationPresentation.options(for: content).isEmpty)
        content.categoryIdentifier = MentionNotificationPresentation.category
        XCTAssertEqual(MentionNotificationPresentation.options(for: content), [.banner, .list, .sound])
        content.userInfo = [:]
        XCTAssertTrue(MentionNotificationPresentation.options(for: content).isEmpty)
    }
}
#endif
