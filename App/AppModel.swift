import SwiftUI
import Observation
import CloudKit
import Network
import os

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let store: LocalStore
    let service: LibraryService
    private let metadata: any MetadataProviding
    private let logger = Logger(subsystem: "app.clippings.family", category: "sync")
    var snapshot = Snapshot()
    var selectedLibraryKey: String?
    var error: String?
    var loaded = false
    var syncing = false
    var status = "Saved on this device"
    var accountBlocked = false
    var sharingSheet: SharingSheet?
    let cloud: AppleCloudRepository?
    let engine: SyncEngine?
    let mentions: MentionProcessor
    private var subscribed = false
    private var networkMonitor: NWPathMonitor?
    private var retryTask: Task<Void, Never>?
    private var failures = 0
    var userID: String { snapshot.accountID ?? "local-user" }
    var library: Item? { snapshot.libraries.first { $0.key == selectedLibraryKey } ?? snapshot.libraries.first }
    var unread: [Item] { LinkRules.unreadMentions(in: snapshot, userID: userID) }
    init(store: LocalStore = Configuration.store, metadata: any MetadataProviding = MetadataService.shared,
         syncEngine: SyncEngine? = nil, notifier: any MentionNotifying = AppleMentionNotifier()) {
        self.store = store; self.metadata = metadata; service = LibraryService(store: store)
        mentions = MentionProcessor(store: store, notifier: notifier)
        let cloud = syncEngine == nil && Configuration.cloudAvailable ? AppleCloudRepository() : nil
        self.cloud = cloud; engine = syncEngine ?? cloud.map { SyncEngine(store: store, cloud: $0) }
    }
    func start() async {
        if cloud != nil && networkMonitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied { Task { @MainActor in await self?.refresh() } }
            }
            monitor.start(queue: DispatchQueue(label: "app.clippings.connectivity")); networkMonitor = monitor
        }
        await refresh()
    }
    /// A CloudKit wake can arrive before SwiftUI creates a screen or calls start().
    func refreshFromNotification() async -> Bool {
        let previous = snapshot.items
        await refresh()
        return previous != snapshot.items
    }
    func load() async {
        do { snapshot = try await store.read(); loaded = true }
        catch { self.error = error.localizedDescription; loaded = true }
    }
    func perform(_ operation: () async throws -> Void) async {
        do { try await operation(); await refresh() } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        await load()
        guard let engine, !syncing else { return }
        syncing = true; status = "Syncing with iCloud…"
        logger.debug("Starting synchronization")
        defer { syncing = false }
        do {
            try await engine.synchronize()
            accountBlocked = false; failures = 0; retryTask?.cancel()
            await load()
            try await mentions.process(userID: userID)
            if !subscribed, let cloud { try await cloud.subscribe(); subscribed = true }
            let pending = snapshot.pending.count
            status = pending == 0 ? "Up to date with iCloud" : "\(pending) changes waiting to sync"
            logger.debug("Synchronization completed; pending changes: \(pending, privacy: .public)")
        } catch {
            if error as? ClippingsError == .accountChanged { accountBlocked = true }
            status = friendlyCloudError(error)
            logger.notice("Synchronization deferred; error code: \((error as NSError).code, privacy: .public)")
            failures += 1
            retryTask?.cancel()
            if !accountBlocked {
                let retryAfter = max(1, (error as? CKError)?.retryAfterSeconds ?? min(pow(2, Double(min(failures, 8))), 300))
                retryTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(retryAfter)); await self?.refresh() } catch {}
                }
            }
        }
    }
    func friendlyCloudError(_ error: Error) -> String {
        if error is CancellationError { return "Sync paused. Your changes are saved on this device." }
        if error is SyncFailure { return "iCloud couldn’t finish syncing. Your changes are saved and will retry." }
        guard let cloud = error as? CKError else { return error.localizedDescription }
        switch cloud.code {
        case .networkFailure, .networkUnavailable: return "Offline · changes saved on this device"
        case .quotaExceeded: return "iCloud storage is full. Your changes are safe here."
        case .notAuthenticated: return "Sign in to iCloud in Settings to sync."
        case .permissionFailure: return "Sharing permissions changed. Your unsent changes are preserved."
        case .badContainer, .missingEntitlement: return "iCloud needs app configuration. See the developer setup guide."
        default: return "iCloud couldn’t sync yet. Your changes are saved; pull to retry."
        }
    }
    func manageSharing() async {
        guard let cloud, let library else { error = "iCloud sharing requires a signed app with its iCloud container and App Group configured."; return }
        await refresh()
        guard !accountBlocked else { return }
        do {
            // Do not offer an invitation before the library has reached its owner’s database.
            let state = try await store.read()
            guard state.pending[library.key] == nil else { throw ClippingsError.cloud("The library must finish syncing before you can invite your family. Try again when you’re online.") }
            sharingSheet = SharingSheet(share: try await cloud.sharingRecord(for: library), container: cloud.container, title: library.title)
        } catch { self.error = friendlyCloudError(error) }
    }
    func acceptInvitation(_ metadata: CKShare.Metadata) async {
        guard let cloud else { error = "This build needs iCloud configuration before it can accept invitations."; return }
        do {
            let bound = try await store.read().accountID
            try await cloud.accept(metadata, boundAccount: bound); AppEvents.shared.invitation = nil; await refresh()
        } catch { self.error = friendlyCloudError(error) }
    }
    func removeLibrary(_ library: Item) async {
        await perform {
            try await store.transaction { state in
                if state.settings["known:\(library.zone.key)"] == nil && library.zone.scope == .owned {
                    state.items = state.items.filter { $0.value.zone != library.zone }
                    state.pending = state.pending.filter { $0.value.zone != library.zone }
                    state.zones.removeValue(forKey: library.zone.key)
                } else {
                    state.settings["remove:\(library.zone.key)"] = "true"
                    state.zones[library.zone.key]?.available = false
                }
            }
        }
    }
    func createLibrary(_ name: String) async -> Bool {
        do {
            let library = try await service.createLibrary(name: name, userID: userID)
            selectedLibraryKey = library.key; await refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func addLink(url: String, title: String, collection: String?, recipients: Set<String> = []) async -> Bool {
        guard let library else { return false }
        do {
            let saved = try await service.saveLink(url: url, title: title, collection: collection, library: library, userID: userID, recipients: recipients)
            await load()
            Task { await refresh() }
            if !Configuration.isUITesting, let url = URL(string: saved["url"]) {
                Task {
                    if let metadata = try? await self.metadata.metadata(for: url), title.isEmpty {
                        let fetchedTitle = LinkRules.metadataTitle(metadata.title, url: url)
                        await perform {
                            try await store.transaction { state in
                                if let current = state.items[saved.key], !current.deleted, current.fields["title"] == saved.fields["title"] {
                                    _ = state.edit(current, values: ["title": fetchedTitle])
                                }
                            }
                        }
                    }
                }
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
