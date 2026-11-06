import UIKit
import CloudKit
import Observation

@MainActor @Observable
final class AppEvents {
    static let shared = AppEvents()
    var invitation: CKShare.Metadata?
    var invitationError: String?
    var refresh: (() async -> Void)?
    func receive(_ metadata: CKShare.Metadata) { invitation = metadata }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
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
