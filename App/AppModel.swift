import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let store: LocalStore
    let service: LibraryService
    var snapshot = Snapshot()
    var selectedLibraryKey: String?
    var error: String?
    var loaded = false
    var syncing = false
    var status = "Saved on this device"
    var userID: String { snapshot.accountID ?? "local-user" }
    var library: Item? { snapshot.libraries.first { $0.key == selectedLibraryKey } ?? snapshot.libraries.first }
    var unread: [Item] { LinkRules.unreadMentions(in: snapshot, userID: userID) }
    init(store: LocalStore = Configuration.store) { self.store = store; service = LibraryService(store: store) }
    func load() async {
        do { snapshot = try await store.read(); loaded = true }
        catch { self.error = error.localizedDescription; loaded = true }
    }
    func perform(_ operation: () async throws -> Void) async {
        do { try await operation(); await load() } catch { self.error = error.localizedDescription }
    }
    func refresh() async { await load() }
    func createLibrary(_ name: String) async -> Bool {
        do {
            let library = try await service.createLibrary(name: name, userID: userID)
            selectedLibraryKey = library.key; await load(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func addLink(url: String, title: String, collection: String?, recipients: Set<String> = []) async -> Bool {
        guard let library else { return false }
        do {
            let saved = try await service.saveLink(url: url, title: title, collection: collection, library: library, userID: userID, recipients: recipients)
            await load()
            if !Configuration.isUITesting, let url = URL(string: saved["url"]) {
                Task {
                    if let metadata = try? await MetadataService.shared.metadata(for: url), title.isEmpty {
                        await perform { try await service.update(saved, values: ["title": LinkRules.metadataTitle(metadata.title, url: url)]) }
                    }
                }
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
