import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel()
        let controller = UIHostingController(rootView: ShareForm(model: model, complete: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }, cancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }))
        addChild(controller); view.addSubview(controller.view); controller.didMove(toParent: self)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor), controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        Task { await model.load(items: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []) }
    }
}

@MainActor @Observable
final class ShareModel {
    var snapshot = Snapshot()
    var libraryKey = ""
    var collection: String?
    var recipients: Set<String> = []
    var url = ""
    var title = ""
    var loading = true
    var saving = false
    var saved = false
    var syncing = false
    var message = ""
    var error: String?
    private let operationID = UUID().uuidString
    private let store = Configuration.store
    var library: Item? { snapshot.libraries.first { $0.key == libraryKey } }
    var writableLibraries: [Item] { snapshot.libraries.filter { snapshot.zones[$0.zone.key]?.canWrite != false } }
    var userID: String { snapshot.accountID ?? "local-user" }
    func load(items: [NSExtensionItem]) async {
        defer { loading = false }
        guard Configuration.groupURL != nil else { error = "Your libraries aren’t available in this build. Open Clippings to finish setting up family sharing."; return }
        do {
            snapshot = try await store.read(); libraryKey = writableLibraries.first?.key ?? ""
            let providers = items.flatMap { $0.attachments ?? [] }
            for type in [UTType.url.identifier, UTType.plainText.identifier] {
                for provider in providers.prefix(12) where provider.hasItemConformingToTypeIdentifier(type) {
                    let text = await AttachmentReader.text(from: provider, type: type)
                    if let text, let valid = try? SharedInput.url(in: text) {
                        url = valid.absoluteString
                        return
                    }
                }
            }
            error = "This share doesn’t contain a website link. In the original app, choose Share link or Copy link and try again."
        } catch { self.error = error.localizedDescription }
    }
    func save() async {
        guard !saving, !saved, let library else { return }
        saving = true
        defer { saving = false }
        do {
            let service = LibraryService(store: store)
            _ = try await service.saveLink(url: url, title: title, collection: collection, library: library, userID: userID, recipients: recipients, operationID: operationID)
            saved = true; message = "Saved to \(library.title)."
            guard Configuration.cloudAvailable else { message += " It will sync when Clippings is connected to iCloud."; return }
            syncing = true
            let engine = SyncEngine(store: store, cloud: AppleCloudRepository())
            let upload = Task { try await engine.synchronize() }
            let deadline = Task { @MainActor in
                try await Task.sleep(for: .seconds(10))
                if syncing { upload.cancel(); syncing = false; message = "Saved on this device. Sync will continue when Clippings is next active." }
            }
            do { try await upload.value; if syncing { message = "Saved to \(library.title) and synced with iCloud." } }
            catch { message = "Saved on this device. Sync will retry when Clippings is next active." }
            deadline.cancel(); syncing = false
        } catch { self.error = error.localizedDescription }
    }
}

struct ShareForm: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: ShareModel
    let complete: () -> Void
    let cancel: () -> Void
    var body: some View {
        NavigationStack {
            Group {
                if model.loading { ProgressView("Getting your libraries…") }
                else if model.saved {
                    ContentUnavailableView {
                        Label("A good find, saved.", systemImage: "checkmark.circle")
                    } description: {
                        Text(model.message)
                        if model.syncing { ProgressView("Syncing with iCloud…") }
                    } actions: { Button("Done", action: complete).buttonStyle(.borderedProminent) }
                }
                else if model.writableLibraries.isEmpty {
                    ContentUnavailableView("A family library comes first", systemImage: "person.2", description: Text("Open Clippings once to create a library or accept an invitation with permission to add links. Then share again."))
                } else {
                    Form {
                        Section("Link") {
                            TextField("Website address", text: $model.url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            TextField("Title (optional)", text: $model.title)
                        }
                        Section {
                            Picker("Library", selection: $model.libraryKey) { ForEach(model.writableLibraries) { Text($0.title).tag($0.key) } }
                                .onChange(of: model.libraryKey) { _, _ in model.collection = nil; model.recipients = [] }
                            Picker("Collection", selection: $model.collection) {
                                Text("Unfiled").tag(String?.none)
                                if let library = model.library {
                                    ForEach(model.snapshot.visible(.collection, zone: library.zone).sorted { $0.title < $1.title }) { Text($0.title).tag(Optional($0.id)) }
                                }
                            }
                        }
                        if let library = model.library {
                            let members = model.snapshot.zones[library.zone.key]?.members.filter { $0.id != model.userID } ?? []
                            if !members.isEmpty {
                                Section("Mention someone") {
                                    ForEach(members) { member in
                                        Toggle(member.name, isOn: Binding(get: { model.recipients.contains(member.id) }, set: { if $0 { model.recipients.insert(member.id) } else { model.recipients.remove(member.id) } }))
                                    }
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("Save to Clippings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(model.saved ? "Done" : "Cancel", action: model.saved ? complete : cancel) }
                    if !model.saved {
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await model.save() } }.disabled(model.loading || model.saving || model.url.isEmpty || model.library == nil) }
                    }
                }
                .alert("Couldn’t save this link", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        }.tint(colorScheme == .dark ? Color(red: 0.52, green: 0.78, blue: 0.63) : Color(red: 0.18, green: 0.38, blue: 0.30))
    }
}
