import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection: String?
    @State private var oldest = false
    @State private var addingLink = false
    @State private var addingCollection = false
    @State private var editingCollection: Item?
    @State private var deleting: Item?
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: "all") { Label("All links", systemImage: "link") }
                    NavigationLink(value: "unfiled") { Label("Unfiled", systemImage: "tray") }
                }
                Section("Collections") {
                    if let library = model.library {
                        ForEach(model.snapshot.visible(.collection, zone: library.zone).filter { query.isEmpty || $0.title.localizedStandardContains(query) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { collection in
                            NavigationLink(value: collection.id) {
                                HStack(spacing: 12) {
                                    CollectionBadge(icon: collection["icon"])
                                    Text(collection.title)
                                    Spacer()
                                    Text("\(model.snapshot.visible(.link, zone: library.zone).filter { $0["collection"] == collection.id }.count)").foregroundStyle(.secondary)
                                }
                            }.contextMenu {
                                Button("Edit collection", systemImage: "pencil") { editingCollection = collection }
                                Button("Delete collection", systemImage: "trash", role: .destructive) { deleting = collection }
                            }
                        }
                    }
                    Button { addingCollection = true } label: { Label("New collection", systemImage: "folder.badge.plus") }.accessibilityIdentifier("newCollection").disabled(model.library.map { model.snapshot.zones[$0.zone.key]?.canWrite == false } ?? true)
                }
                Section {
                    Label(model.status, systemImage: model.syncing ? "arrow.triangle.2.circlepath" : model.cloud == nil ? "internaldrive" : model.status == "Up to date with iCloud" ? "checkmark.icloud" : "icloud.slash").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(model.library?.title ?? "Library")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a collection")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button { addingLink = true } label: { Label("Add link", systemImage: "plus") }.accessibilityIdentifier("addLink").disabled(model.library.map { model.snapshot.zones[$0.zone.key]?.canWrite == false } ?? true) }
            }
            .refreshable { await model.refresh() }
        } detail: {
            LinkListView(collection: selection == "all" ? nil : selection, oldest: $oldest, addingLink: $addingLink)
        }
        .onChange(of: model.library?.key) { _, _ in selection = nil }
        .sheet(isPresented: $addingLink) { AddLinkView(collection: selection == "all" || selection == "unfiled" ? nil : selection) }
        .sheet(isPresented: $addingCollection) { CollectionEditor() }
        .sheet(item: $editingCollection) { CollectionEditor(item: $0) }
        .confirmationDialog("Delete this collection? Its links will stay in Unfiled.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
            Button("Delete collection", role: .destructive) {
                Task { await model.perform { try await model.service.delete(item) }; selection = nil }
            }
        }
    }
}
struct LinkListView: View {
    @Environment(AppModel.self) private var model
    let collection: String?
    @Binding var oldest: Bool
    @Binding var addingLink: Bool
    @State private var query = ""
    @State private var deleting: Item?
    private var links: [Item] {
        guard let library = model.library else { return [] }
        return LinkRules.links(in: model.snapshot, zone: library.zone, query: query, collection: collection, oldestFirst: oldest)
    }
    private var title: String { collection == "unfiled" ? "Unfiled" : model.snapshot.visible(.collection).first { $0.id == collection }?.title ?? "All links" }
    var body: some View {
        NavigationStack {
            List {
                if !links.isEmpty {
                    Section {
                        ForEach(links) { link in
                            NavigationLink { LinkDetailView(item: link) } label: { LinkRow(item: link) }
                                .contextMenu {
                                    if let url = URL(string: link["url"]) { ShareLink(item: url) }
                                    Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.string = link["url"] }
                                    Button("Delete link", systemImage: "trash", role: .destructive) { deleting = link }
                                }
                                .swipeActions { Button("Delete", role: .destructive) { deleting = link } }
                        }
                    } header: { Text("\(links.count) \(links.count == 1 ? "link" : "links")") }
                }
            }
            .overlay {
                if links.isEmpty {
                    ScrollableEmptyState {
                        if query.isEmpty {
                            EmptyLibraryMessage(canAdd: model.library.map { model.snapshot.zones[$0.zone.key]?.canWrite != false } ?? false) { addingLink = true }
                        } else { ContentUnavailableView.search(text: query) }
                    }
                }
            }
            .navigationTitle(title).searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search links and notes").accessibilityIdentifier("linkList")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu { Picker("Sort links", selection: $oldest) { Text("Newest first").tag(false); Text("Oldest first").tag(true) } } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    Button { addingLink = true } label: { Label("Add link", systemImage: "plus") }.accessibilityIdentifier("addLinkDetail").disabled(model.library.map { model.snapshot.zones[$0.zone.key]?.canWrite == false } ?? true)
                }
            }.refreshable { await model.refresh() }
            .confirmationDialog("Delete this link for everyone?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
                Button("Delete link", role: .destructive) { Task { await model.perform { try await model.service.delete(item) } } }
            }
        }
    }
}

private struct EmptyLibraryMessage: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let canAdd: Bool
    let add: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label(typeSize.isAccessibilitySize ? "No links yet" : "A little space for good finds", systemImage: "bookmark")
        } description: {
            Text(canAdd ? (typeSize.isAccessibilitySize ? "Save a good find for your family." : "Save something you’d love to come back to—or share with your family.") : "Your family’s saved links will appear here.")
        } actions: {
            if canAdd { Button(typeSize.isAccessibilitySize ? "Add a link" : "Save your first link", action: add).buttonStyle(.borderedProminent).accessibilityIdentifier("addFirstLink") }
        }
    }
}
