import SwiftUI

struct LibrarySplitView: View {
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
    var showCollections: (() -> Void)? = nil
    @State private var query = ""
    @State private var selectedLink: Item?
    private var links: [Item] {
        guard let library = model.library else { return [] }
        return LinkRules.links(in: model.snapshot, zone: library.zone, query: query, collection: collection, oldestFirst: oldest)
    }
    private var title: String { collection == "unfiled" ? "Unfiled" : model.snapshot.visible(.collection).first { $0.id == collection }?.title ?? "All links" }
    var body: some View {
        NavigationStack {
            List {
                if !links.isEmpty {
                    NewspaperMasthead().listRowBackground(Color.clear).listRowSeparator(.hidden)
                    Section {
                        ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                            ClippingListRow(link: link, featured: index < 5) { selectedLink = link }
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 16, trailing: 18))
                        }
                    } header: {
                        ViewThatFits(in: .horizontal) {
                            HStack { Text(oldest ? "From the archives" : "Freshly clipped").font(.system(.title3, design: .serif)).italic(); Spacer(); Text(oldest ? "Oldest first" : "Newest first").font(.caption2) }
                            Text(oldest ? "From the archives" : "Freshly clipped").font(.system(.title3, design: .serif)).italic()
                        }.textCase(nil).foregroundStyle(Design.secondaryInk).padding(.bottom, 8)
                    }
                }
            }
            .listStyle(.plain).listSectionSpacing(10).scrollContentBackground(.hidden).background(Design.paper)
            .navigationDestination(isPresented: Binding(get: { selectedLink != nil }, set: { if !$0 { selectedLink = nil } })) {
                if let selectedLink { LinkDetailView(item: selectedLink) }
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
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.paper, for: .navigationBar)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search links and notes").accessibilityIdentifier("linkList")
            .toolbar {
                if let showCollections { ToolbarItem(placement: .topBarLeading) { Button(action: showCollections) { Label("Collections", systemImage: "tray.full") }.accessibilityIdentifier("showCollections") } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu { Picker("Sort links", selection: $oldest) { Text("Newest first").tag(false); Text("Oldest first").tag(true) } } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    Button { addingLink = true } label: { Label("Add link", systemImage: "plus") }.accessibilityIdentifier(showCollections == nil ? "addLinkDetail" : "addLink").disabled(model.library.map { model.snapshot.zones[$0.zone.key]?.canWrite == false } ?? true)
                }
            }.refreshable { await model.refresh() }
        }
    }
}

private struct ClippingListRow: View {
    @Environment(AppModel.self) private var model
    let link: Item
    let featured: Bool
    let open: () -> Void
    @State private var confirmingDelete = false
    private var canWrite: Bool { model.snapshot.zones[link.zone.key]?.canWrite != false }

    var body: some View {
        Button(action: open) { ClippingCard(item: link, featured: featured) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clipping-\(link.id)")
            .contextMenu {
                if let url = URL(string: link["url"]) { ShareLink(item: url) }
                Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.string = link["url"] }
                if canWrite {
                    Button("Delete link", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if canWrite {
                    // Confirm first, without the destructive role's automatic row-removal animation.
                    Button("Delete", systemImage: "trash") { confirmingDelete = true }
                        .tint(.red)
                }
            }
            // Keep the presentation source on the card, including after the list scrolls.
            .confirmationDialog("Delete this link for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete link", role: .destructive) {
                    Task { await model.perform { try await model.service.delete(link) } }
                }
                Button("Cancel", role: .cancel) { }
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
