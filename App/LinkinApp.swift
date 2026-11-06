import SwiftUI

@main
struct LinkinApp: App {
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
                    await model.load()
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        }
    }
}
struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Group {
            if !model.loaded { ProgressView("Opening your library…") }
            else if model.library == nil { OnboardingView() }
            else {
                TabView {
                    LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
                    MentionsView().tabItem { Label("Mentions", systemImage: "at") }.badge(model.unread.count)
                    FamilyView().tabItem { Label("Family", systemImage: "person.2") }
                }
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
