import UserNotifications
import CloudKit
import CryptoKit
import UIKit
import os

struct AppleMentionNotifier: MentionNotifying {
    private func identifier(_ id: String) -> String { "mention-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    func schedule(id: String, linkKey: String) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        let key = identifier(id)
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        if pending.contains(where: { $0.identifier == key }) || delivered.contains(where: { $0.request.identifier == key }) { return true }
        let content = UNMutableNotificationContent()
        content.title = "A link with you in mind"
        content.body = "Someone in your family mentioned you. Open linkin to see their find."
        content.sound = .default
        content.userInfo = ["linkKey": linkKey]
        try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        return true
    }
    func remove(ids: [String]) async {
        let keys = ids.map(identifier)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: keys)
        center.removeDeliveredNotifications(withIdentifiers: keys)
    }
}

extension AppleCloudRepository {
    func subscribe() async throws {
        for (database, id) in [(container.privateCloudDatabase, "linkin-private-v1"), (container.sharedCloudDatabase, "linkin-shared-v1")] {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            // No alert body, sound or badge: every database push is silent.
            _ = try await database.save(subscription)
        }
    }
}

@MainActor
extension AppModel {
    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if allowed { UIApplication.shared.registerForRemoteNotifications(); await refresh() }
            else { error = "Notifications are off. You can enable them for linkin in Settings. Your mentions are always available in the app." }
        } catch { self.error = error.localizedDescription }
    }
}
