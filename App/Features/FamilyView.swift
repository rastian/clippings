import SwiftUI

struct FamilyView: View {
    @Environment(AppModel.self) private var model
    @State private var newLibrary = false
    @State private var name = ""
    @State private var removing = false
    @State private var exportURL: URL?
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
                if let library = model.library {
                    Section("Sharing") {
                        Button { Task { await model.manageSharing() } } label: { Label("Invite & manage family", systemImage: "person.badge.plus") }
                        ForEach(model.snapshot.zones[library.zone.key]?.members ?? []) { member in
                            LabeledContent(member.id == model.userID ? "You" : member.name, value: member.role + (member.canWrite ? "" : " · View only"))
                        }
                        Button(library.zone.scope == .owned ? "Delete library" : "Leave library", role: .destructive) { removing = true }
                    }
                }
                Section("iCloud") {
                    Label(model.status, systemImage: "icloud")
                    Text("Family sharing uses your Apple Account. Only people invited to your library can access it.").foregroundStyle(.secondary)
                    Button("Refresh") { Task { await model.refresh() } }
                    Button("Enable mention notifications") { Task { await model.enableNotifications() } }
                    Text("Only explicit mentions create alerts. Delivery depends on iOS background access; unread mentions always refresh when you open linkin.").font(.footnote).foregroundStyle(.secondary)
                    if !model.snapshot.pending.isEmpty || !(model.snapshot.recovered ?? [:]).isEmpty {
                        Text("\(model.snapshot.pending.count) pending changes · \((model.snapshot.recovered ?? [:]).count) recovered items").font(.footnote)
                        Button("Prepare a recovery copy") {
                            Task {
                                do {
                                    let data = try JSONEncoder().encode(try await model.store.read())
                                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("linkin-recovery.json")
                                    try data.write(to: url, options: [.atomic, .completeFileProtection]); exportURL = url
                                } catch { model.error = error.localizedDescription }
                            }
                        }
                        if let exportURL { ShareLink("Export recovery copy", item: exportURL) }
                    }
                }
                Section {
                    LabeledContent("App", value: "linkin 1.0")
                    Text("Your family’s corner of the internet.").foregroundStyle(.secondary)
                    Label("No advertising or tracking", systemImage: "hand.raised")
                }
            }.navigationTitle("Family")
                .confirmationDialog(model.library?.zone.scope == .owned ? "Delete this library and all its links for everyone?" : "Leave this shared library?", isPresented: $removing, titleVisibility: .visible) {
                    Button(model.library?.zone.scope == .owned ? "Delete library" : "Leave library", role: .destructive) { if let library = model.library { Task { await model.removeLibrary(library) } } }
                }
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
                            .swipeActions { Button("Mark read", systemImage: "checkmark") { Task { await model.perform { try await model.service.markRead(mention, userID: model.userID) } } }.tint(Design.accent) }
                    }
                }
            }.overlay { if model.unread.isEmpty { ContentUnavailableView("You’re all caught up", systemImage: "at", description: Text("When someone saves a link with you in mind, you’ll find it here.")) } }
                .navigationTitle("For you").refreshable { await model.refresh() }
        }
    }
}
