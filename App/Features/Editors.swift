import SwiftUI

struct AddLinkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State var collection: String?
    @State private var recipients: Set<String> = []
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $url).keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("linkURL")
                    TextField("Title (optional)", text: $title).accessibilityIdentifier("linkTitle")
                } header: { Text("A good find") } footer: { Text("The link saves immediately. A preview is added when the website allows it.") }
                if let library = model.library {
                    Section {
                        Picker("Collection", selection: $collection) {
                            Text("Unfiled").tag(String?.none)
                            ForEach(model.snapshot.visible(.collection, zone: library.zone).sorted { $0.title < $1.title }) { Text($0.title).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("collectionPicker")
                    }
                    let members = model.snapshot.zones[library.zone.key]?.libraryMembers.filter { $0.id != model.userID } ?? []
                    if !members.isEmpty {
                        Section {
                            ForEach(members) { member in
                                Toggle(member.name, isOn: Binding(get: { recipients.contains(member.id) }, set: { if $0 { recipients.insert(member.id) } else { recipients.remove(member.id) } })).accessibilityIdentifier("mentionRecipient-\(member.id)")
                            }
                        } header: { Text("Mention someone") } footer: { Text("Only the people you mention may receive a notification.") }
                    }
                }
            }.navigationTitle("Save a link").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            saving = true
                            Task {
                                if await model.addLink(url: url, title: title, collection: collection, recipients: recipients) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred(); dismiss()
                                }
                                saving = false
                            }
                        }.disabled(saving || url.isEmpty).accessibilityIdentifier("saveLink")
                    }
                }
        }
    }
}
struct MentionPeopleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @State private var recipients: Set<String> = []
    @State private var saving = false
    @State private var error: String?
    private var members: [Member] { model.snapshot.zones[item.zone.key]?.libraryMembers.filter { $0.id != model.userID } ?? [] }
    private var mentioned: Set<String> {
        Set(model.snapshot.visible(.mention, zone: item.zone).filter { $0["link"] == item.id }.map { $0["recipient"] })
    }
    private var selected: Set<String> { recipients.intersection(members.map(\.id)).subtracting(mentioned) }
    private var canWrite: Bool { model.snapshot.zones[item.zone.key]?.canWrite == true && model.snapshot.zones[item.zone.key]?.available == true }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(members) { member in
                        Toggle(isOn: Binding(get: { mentioned.contains(member.id) || recipients.contains(member.id) }, set: { if $0 { recipients.insert(member.id) } else { recipients.remove(member.id) } })) {
                            VStack(alignment: .leading) {
                                Text(member.name)
                                Text(mentioned.contains(member.id) ? "Already mentioned" : member.role).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(mentioned.contains(member.id) || !canWrite || saving).accessibilityIdentifier("mentionRecipient-\(member.id)")
                    }
                } header: { Text(item.title) } footer: {
                    Text(canWrite ? "Only the people you select may receive a notification. People already mentioned won’t be notified again." : "You need editing access to mention someone in this library.")
                }
            }.navigationTitle("Mention someone").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Sending…" : "Send") {
                            saving = true
                            let selection = selected
                            Task {
                                do {
                                    try await model.service.mention(item, recipients: selection, userID: model.userID)
                                    await model.load()
                                    Task { await model.refresh() }
                                    dismiss()
                                } catch { self.error = error.localizedDescription }
                                saving = false
                            }
                        }.disabled(saving || selected.isEmpty || !canWrite).accessibilityIdentifier("sendMentions")
                    }
                }
                .interactiveDismissDisabled(saving)
                .alert("Couldn’t send mention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
}
struct CollectionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var item: Item?
    @State private var name = ""
    @State private var icon = "folder"
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Collection name", text: $name).accessibilityIdentifier("collectionName") }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 16) {
                        ForEach(Design.icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol).font(.title2).frame(minWidth: 44, minHeight: 44)
                                    .background(icon == symbol ? Design.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).foregroundStyle(Design.accent).accessibilityLabel(Design.iconNames[symbol] ?? "Collection icon").accessibilityAddTraits(icon == symbol ? .isSelected : [])
                        }
                    }.padding(.vertical, 8)
                }
            }.navigationTitle(item == nil ? "New collection" : "Edit collection").navigationBarTitleDisplayMode(.inline)
                .onAppear { if let item { name = item.title; icon = item["icon"] } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saving = true
                            Task {
                                do {
                                    if let item { try await model.service.update(item, values: ["title": name, "icon": icon]) }
                                    else if let library = model.library { try await model.service.createCollection(name: name, icon: icon, library: library, userID: model.userID) }
                                    await model.refresh(); dismiss()
                                } catch { model.error = error.localizedDescription }
                                saving = false
                            }
                        }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("saveCollection")
                    }
                }
        }
    }
}
