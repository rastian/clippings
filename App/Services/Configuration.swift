import Foundation

struct Configuration {
    static let containerID = Bundle.main.object(forInfoDictionaryKey: "LinkinContainer") as? String ?? "iCloud.app.linkin.family"
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "LinkinAppGroup") as? String ?? "group.app.linkin.family"
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }
    static var groupURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) }
    static var cloudAvailable: Bool { !isUITesting && Bundle.main.object(forInfoDictionaryKey: "LinkinCloudEnabled") as? String == "YES" && groupURL != nil }
    static var directory: URL {
        if isUITesting { return FileManager.default.temporaryDirectory.appendingPathComponent("linkin-ui-tests", isDirectory: true) }
        return groupURL ?? URL.applicationSupportDirectory.appendingPathComponent("linkin", isDirectory: true)
    }
    static var store: LocalStore { LocalStore(url: directory.appendingPathComponent("library.sqlite")) }
}
