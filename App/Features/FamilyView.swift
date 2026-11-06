import SwiftUI

struct FamilyView: View {
    @Environment(AppModel.self) private var model
    @State private var newLibrary = false
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Your libraries") {
                    ForEach(model.snapshot.libraries) { library in
                        Button { model.selectedLibraryKey = library.key } label: {
                            HStack { Label(library.title, systemImage: "person.2"); Spacer(); if model.library?.key == library.key { Image(systemName: "checkmark") } }
                        }
                    }
                    Button("Create another library", systemImage: "plus") { newLibrary = true }
                }
                Section("iCloud") {
                    Label(model.status, systemImage: "icloud")
                    Text("Family sharing uses your Apple Account. Only people invited to your library can access it.").foregroundStyle(.secondary)
                    Button("Refresh") { Task { await model.refresh() } }
                }
                Section {
                    LabeledContent("App", value: "linkin 1.0")
                    Text("Your family’s corner of the internet.").foregroundStyle(.secondary)
                    Label("No advertising or tracking", systemImage: "hand.raised")
                }
            }.navigationTitle("Family")
                .alert("New library", isPresented: $newLibrary) {
                    TextField("Library name", text: $name)
                    Button("Create") { Task { _ = await model.createLibrary(name); name = "" } }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
struct MentionsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.unread) { mention in
                    if let link = model.snapshot.items["\(mention.zone.key)|\(mention["link"])"] {
                        NavigationLink { LinkDetailView(item: link) } label: { LinkRow(item: link) }
                            .swipeActions { Button("Mark read", systemImage: "checkmark") { Task { await model.perform { try await model.service.update(mention, values: ["read": "true"]) } } }.tint(Design.accent) }
                    }
                }
            }.overlay { if model.unread.isEmpty { ContentUnavailableView("You’re all caught up", systemImage: "at", description: Text("When someone saves a link with you in mind, you’ll find it here.")) } }
                .navigationTitle("For you").refreshable { await model.refresh() }
        }
    }
}
