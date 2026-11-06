import Foundation

public protocol MentionNotifying: Sendable {
    /// Return false when notification permission is absent; unread state remains available.
    func schedule(id: String, linkKey: String) async throws -> Bool
    func remove(ids: [String]) async
}
public actor MentionProcessor {
    private var processing = false
    let store: LocalStore
    let notifier: any MentionNotifying
    public init(store: LocalStore, notifier: any MentionNotifying) { self.store = store; self.notifier = notifier }
    public func process(userID: String) async throws {
        guard !processing else { return }
        processing = true; defer { processing = false }
        let state = try await store.read()
        let unread = LinkRules.unreadMentions(in: state, userID: userID)
        let unreadKeys = Set(unread.map(\.key))
        let completed = state.items.values.filter { $0.kind == .mention && $0["recipient"] == userID && !unreadKeys.contains($0.key) }.map(\.key)
        await notifier.remove(ids: completed)
        for mention in unread where LinkRules.shouldNotify(mention, userID: userID, notified: state.notified) {
            if try await notifier.schedule(id: mention.key, linkKey: "\(mention.zone.key)|\(mention["link"])") {
                try await store.transaction { $0.notified.insert(mention.key) }
            }
        }
    }
}
