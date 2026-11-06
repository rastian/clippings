import Foundation

struct Configuration {
    static let containerID = Bundle.main.object(forInfoDictionaryKey: "ClippingsContainer") as? String ?? "iCloud.app.clippings.family"
    static let groupID = Bundle.main.object(forInfoDictionaryKey: "ClippingsAppGroup") as? String ?? "group.app.clippings.family"
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }
    static var groupURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) }
    static var cloudAvailable: Bool { !isUITesting && Bundle.main.object(forInfoDictionaryKey: "ClippingsCloudEnabled") as? String == "YES" && groupURL != nil }
    static var directory: URL {
        if isUITesting { return FileManager.default.temporaryDirectory.appendingPathComponent("clippings-ui-tests", isDirectory: true) }
        return groupURL ?? URL.applicationSupportDirectory.appendingPathComponent("clippings", isDirectory: true)
    }
    static var store: LocalStore { LocalStore(url: directory.appendingPathComponent("library.sqlite")) }
}
