import SwiftUI
import CloudKit

@main
struct LinkinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environment(model).tint(Design.accent)
                .task {
                    #if DEBUG
                    if Configuration.isUITesting && ProcessInfo.processInfo.arguments.contains("--reset") {
                        try? await model.store.transaction { $0 = Snapshot() }
                    }
                    #endif
                    await model.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    model.accountBlocked = true; Task { await model.refresh() }
                }
                .onOpenURL { url in
                    guard let cloud = model.cloud, url.scheme == "https", url.host == "www.icloud.com" || url.host == "icloud.com" else { return }
                    Task {
                        do { AppEvents.shared.receive(try await cloud.container.shareMetadata(for: url)) }
                        catch { model.error = error.localizedDescription }
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        }
    }
}
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationLink: Item?
    var body: some View {
        @Bindable var model = model
        Group {
            if !model.loaded { ProgressView("Opening your library…") }
            else if model.accountBlocked {
                ContentUnavailableView {
                    Label("Your iCloud account changed", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: { Text("Sign back into the original Apple Account in Settings to access this library. Your pending changes are preserved on this device.") }
                actions: { Button("Check again") { Task { await model.refresh() } } }
            }
            else if model.library == nil { OnboardingView() }
            else {
                TabView {
                    LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
                    MentionsView().tabItem { Label("Mentions", systemImage: "at") }.badge(model.unread.count)
                    FamilyView().tabItem { Label("Family", systemImage: "person.2") }
                }
            }
        }
        .onChange(of: AppEvents.shared.selectedLinkKey) { _, _ in presentPendingNotification() }
        .onChange(of: model.snapshot.items.count) { _, _ in presentPendingNotification() }
        .sheet(item: $notificationLink) { item in
            NavigationStack { LinkDetailView(item: item).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { notificationLink = nil } } } }
        }
        .sheet(item: $model.sharingSheet) { sheet in
            CloudSharingView(sheet: sheet, onFinish: { Task { await model.refresh() } }, onError: { model.error = $0 })
        }
        .confirmationDialog("Join this family library?", isPresented: Binding(get: { AppEvents.shared.invitation != nil }, set: { if !$0 { AppEvents.shared.invitation = nil } }), titleVisibility: .visible) {
            Button("Join library") { if let invitation = AppEvents.shared.invitation { Task { await model.acceptInvitation(invitation) } } }
            Button("Cancel", role: .cancel) { AppEvents.shared.invitation = nil }
        } message: { Text("Your Apple Account will be visible to the other participants.") }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func presentPendingNotification() {
        if !model.accountBlocked, let key = AppEvents.shared.selectedLinkKey, let item = model.snapshot.items[key], !item.deleted {
            notificationLink = item; AppEvents.shared.selectedLinkKey = nil
        }
    }

}
