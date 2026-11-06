import SwiftUI
import LinkPresentation

struct LinkDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @State private var note = ""
    @State private var title = ""
    @State private var summary = ""
    @State private var collection: String?
    @State private var metadata: LPLinkMetadata?
    @State private var deleting = false
    @State private var mentioning = false
    @State private var edited = false
    private var canWrite: Bool { model.snapshot.zones[item.zone.key]?.canWrite != false }
    private var current: Item { model.snapshot.items[item.key] ?? item }
    var body: some View {
        Form {
            Section {
                if let metadata { NativeLinkPreview(metadata: metadata) }
                else { LinkRow(item: current) }
                if let url = try? LinkRules.validatedURL(current["url"]) {
                    Link(destination: url) { Label("Open website", systemImage: "safari") }
                    ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                }
                Button { UIPasteboard.general.string = current["url"] } label: { Label("Copy link", systemImage: "doc.on.doc") }
            }
            if model.snapshot.zones[item.zone.key]?.libraryMembers.contains(where: { $0.id != model.userID }) == true {
                Section {
                    Button { mentioning = true } label: { Label("Mention someone", systemImage: "at") }
                        .disabled(!canWrite).accessibilityIdentifier("mentionSomeone")
                } footer: {
                    if !canWrite { Text("You need editing access to mention someone in this library.") }
                }
            }
            Section("Details") {
                TextField("Title", text: $title, axis: .vertical).accessibilityIdentifier("editLinkTitle").onChange(of: title) { _, _ in edited = true }
                TextField("Description (optional)", text: $summary, axis: .vertical).accessibilityIdentifier("editLinkSummary").onChange(of: summary) { _, _ in edited = true }
                Picker("Collection", selection: $collection) {
                    Text("Unfiled").tag(String?.none)
                    ForEach(model.snapshot.visible(.collection, zone: item.zone).sorted { $0.title < $1.title }) { Text($0.title).tag(Optional($0.id)) }
                }.accessibilityIdentifier("moveCollection").onChange(of: collection) { _, _ in edited = true }
            }.disabled(!canWrite)
            Section {
                TextField("Something to remember…", text: $note, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("personalNote").onChange(of: note) { _, _ in edited = true }
            } header: { Text("Your private note") } footer: { Text("Only you can see this note. It stays in your private iCloud storage.") }
            Section {
                LabeledContent("Added by", value: authorName)
                LabeledContent("Saved", value: current.date.formatted(date: .abbreviated, time: .shortened))
            }
            if canWrite { Section { Button("Delete link", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteLink") } }
        }.scrollContentBackground(.hidden).background(Design.paper)
            .navigationTitle("Saved link").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $mentioning) { MentionPeopleView(item: current) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save changes") {
                        Task {
                            do {
                                if canWrite {
                                    try await model.service.update(current, values: ["title": title, "summary": summary, "collection": collection, "updated": String(Date().timeIntervalSince1970)])
                                }
                                try await model.service.saveNote(for: current, text: note, userID: model.userID)
                                await model.refresh(); edited = false
                            } catch { model.error = error.localizedDescription }
                        }
                    }.disabled(!edited).accessibilityIdentifier("saveChanges")
                }
            }
            .task {
                title = current.title; summary = current["summary"]
                collection = model.snapshot.visible(.collection, zone: item.zone).contains { $0.id == current["collection"] } ? current["collection"] : nil
                note = model.snapshot.visible(.note).first { $0["link"] == item.key }?["text"] ?? ""
                edited = false
                if !Configuration.isUITesting, let url = try? LinkRules.validatedURL(current["url"]) {
                    let original = current
                    metadata = try? await MetadataService.shared.metadata(for: url)
                    if canWrite, original.title == original["domain"], let fetched = metadata?.title, !fetched.isEmpty {
                        await model.perform {
                            try await model.store.transaction { state in
                                if let existing = state.items[original.key], !existing.deleted, existing.fields["title"] == original.fields["title"] {
                                    _ = state.edit(existing, values: ["title": LinkRules.metadataTitle(fetched, url: url)])
                                }
                            }
                        }
                        if title == original.title { title = model.snapshot.items[original.key]?.title ?? title }
                    }
                }
            }
            .confirmationDialog("Delete this link for everyone?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete link", role: .destructive) { Task { await model.perform { try await model.service.delete(current) }; if model.error == nil { dismiss() } } }
            }
    }
    private var authorName: String {
        current["author"] == model.userID ? "You" : model.snapshot.zones[item.zone.key]?.libraryMembers.first { $0.id == current["author"] }?.name ?? "Family member"
    }
}
