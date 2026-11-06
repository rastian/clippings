import SwiftUI

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        if sizeClass == .compact { PhoneLibraryView() }
        else { LibrarySplitView() }
    }
}

struct PhoneLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var collection: String?
    @State private var oldest = false
    @State private var addingLink = false
    @State private var showingCollections = false
    @State private var addingCollection = false
    @State private var editing: Item?
    @State private var deleting: Item?
    private var canWrite: Bool { model.library.map { model.snapshot.zones[$0.zone.key]?.canWrite != false } ?? false }
    private var collections: [Item] { model.snapshot.visible(.collection, zone: model.library?.zone).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var body: some View {
        LinkListView(collection: collection, oldest: $oldest, addingLink: $addingLink, showCollections: { showingCollections = true })
            .sheet(isPresented: $addingLink) { AddLinkView(collection: collection == "unfiled" ? nil : collection) }
            .sheet(isPresented: $showingCollections) {
                NavigationStack {
                    List {
                        Section {
                            selection("All links", icon: "newspaper", id: nil)
                            selection("Unfiled", icon: "tray", id: "unfiled")
                        }
                        Section("Collections") {
                            ForEach(collections) { item in
                                selection(item.title, icon: item["icon"].isEmpty ? "folder" : item["icon"], id: item.id)
                                    .contextMenu {
                                        if canWrite {
                                            Button("Edit collection", systemImage: "pencil") { editing = item }
                                            Button("Delete collection", systemImage: "trash", role: .destructive) { deleting = item }
                                        }
                                    }
                            }
                            Button { addingCollection = true } label: { Label("New collection", systemImage: "folder.badge.plus") }.accessibilityIdentifier("newCollection").disabled(!canWrite)
                        }
                        Section { Label(model.status, systemImage: "tray").font(.footnote).foregroundStyle(Design.secondaryInk) }
                    }.scrollContentBackground(.hidden).background(Design.paper)
                        .navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingCollections = false } } }
                        .sheet(isPresented: $addingCollection) { CollectionEditor() }
                        .sheet(item: $editing) { CollectionEditor(item: $0) }
                        .confirmationDialog("Delete this collection? Its links will stay in Unfiled.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
                            Button("Delete collection", role: .destructive) { Task { await model.perform { try await model.service.delete(item) }; if collection == item.id { collection = nil } } }
                        }
                }
            }
            .onChange(of: model.library?.key) { _, _ in collection = nil }
    }
    private func selection(_ title: String, icon: String, id: String?) -> some View {
        Button { collection = id; showingCollections = false } label: {
            HStack { Label(title, systemImage: icon); Spacer(); if collection == id { Image(systemName: "checkmark") } }
        }.foregroundStyle(Design.ink).accessibilityIdentifier("collectionChoice-\(title)")
    }
}
