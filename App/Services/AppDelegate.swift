import UIKit
import CloudKit
import Observation
import UserNotifications
import os

@MainActor @Observable
final class AppEvents {
    static let shared = AppEvents()
    var invitation: CKShare.Metadata?
    var invitationError: String?
    var selectedLinkKey: String?
    func openMention(_ key: String?) async { await AppModel.shared.refresh(); selectedLinkKey = key }
    func receive(_ metadata: CKShare.Metadata) { invitation = metadata }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Configuration.cloudAvailable { application.registerForRemoteNotifications() }
        return true
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { completionHandler(.noData); return }
        let completion = BackgroundCompletion(completionHandler)
        Task { @MainActor in
            let deadline = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(20)); completion.finish(.noData) } catch {}
            }
            let changed = await AppModel.shared.refreshFromNotification()
            deadline.cancel(); completion.finish(changed ? .newData : .noData)
        }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger(subsystem: "app.clippings.family", category: "notifications").notice("Remote notification registration unavailable; foreground sync remains enabled.")
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let key = response.notification.request.content.userInfo["linkKey"] as? String
        await AppEvents.shared.openMention(key)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        MentionNotificationPresentation.options(for: notification.request.content)
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        AppEvents.shared.receive(cloudKitShareMetadata)
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let metadata = options.cloudKitShareMetadata { AppEvents.shared.receive(metadata) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SharingSceneDelegate.self
        return config
    }
}
final class SharingSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        AppEvents.shared.receive(cloudKitShareMetadata)
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { AppEvents.shared.receive(metadata) }
    }
}

@MainActor
private final class BackgroundCompletion {
    private var handler: ((UIBackgroundFetchResult) -> Void)?
    init(_ handler: @escaping (UIBackgroundFetchResult) -> Void) { self.handler = handler }
    func finish(_ result: UIBackgroundFetchResult) {
        let callback = handler; handler = nil; callback?(result)
    }
}
