import Foundation

public struct LibraryService: Sendable {
    public let store: LocalStore
    public init(store: LocalStore) { self.store = store }
    @discardableResult
    public func createLibrary(name: String, userID: String, now: Date = Date()) async throws -> Item {
        let name = try LinkRules.name(name)
        return try await store.transaction { state in
            let zone = Zone(name: "clippings-family-" + UUID().uuidString)
            return state.edit(Item(kind: .library, zone: zone), values: ["title": name, "owner": userID, "author": userID, "created": String(now.timeIntervalSince1970)])
        }
    }
    @discardableResult
    public func createCollection(name: String, icon: String, library: Item, userID: String, now: Date = Date()) async throws -> Item {
        let name = try LinkRules.name(name)
        return try await store.transaction { state in
            try Self.validateLibrary(library, state: state)
            return state.edit(Item(kind: .collection, zone: library.zone), values: ["title": name, "icon": icon, "author": userID, "created": String(now.timeIntervalSince1970)])
        }
    }
    /// The supplied operation ID survives extension retries. Canonical URLs prevent repeated saves.
    @discardableResult
    public func saveLink(url: String, title: String = "", collection: String? = nil, library: Item, userID: String,
                         recipients: Set<String> = [], operationID: String = UUID().uuidString, now: Date = Date()) async throws -> Item {
        let validated = try LinkRules.validatedURL(url)
        let title = try LinkRules.text(title, limit: 500, label: "Title")
        let canonical = try LinkRules.canonical(url)
        return try await store.transaction { state in
            try Self.validateLibrary(library, state: state)
            if let collection, !state.visible(.collection, zone: library.zone).contains(where: { $0.id == collection }) { throw ClippingsError.storage("This collection no longer exists. Choose another collection.") }
            let existing = state.visible(.link, zone: library.zone).first { $0["canonical"] == canonical || $0.id == operationID }
            let item: Item
            if let existing {
                if existing.id != operationID && existing["collection"] != (collection ?? "") {
                    item = state.edit(existing, values: ["collection": collection, "updated": String(now.timeIntervalSince1970)])
                } else { item = existing }
            }
            else {
                item = state.edit(Item(id: operationID, kind: .link, zone: library.zone), values: [
                    "url": validated.absoluteString, "canonical": canonical, "title": LinkRules.metadataTitle(title, url: validated),
                    "domain": validated.host() ?? "", "author": userID, "created": String(now.timeIntervalSince1970),
                    "updated": String(now.timeIntervalSince1970), "collection": collection
                ])
            }
            Self.addMentions(for: item, recipients: recipients, userID: userID, now: now, state: &state)
            return item
        }
    }
    /// Any participant with editing access can mention someone on an existing link.
    public func mention(_ link: Item, recipients: Set<String>, userID: String, now: Date = Date()) async throws {
        try await store.transaction { state in
            guard let current = state.items[link.key], current.kind == .link, !current.deleted else {
                throw ClippingsError.storage("This link is no longer available.")
            }
            guard state.zones[current.zone.key]?.available == true, state.zones[current.zone.key]?.canWrite == true else {
                throw ClippingsError.readOnly
            }
            Self.addMentions(for: current, recipients: recipients, userID: userID, now: now, state: &state)
        }
    }
    private static func addMentions(for link: Item, recipients: Set<String>, userID: String, now: Date, state: inout Snapshot) {
        for recipient in recipients where recipient != userID {
            guard state.zones[link.zone.key]?.members.contains(where: { $0.id == recipient }) == true else { continue }
            let mention = Item(id: "mention-\(link.id)-\(recipient)", kind: .mention, zone: link.zone)
            if state.items[mention.key] == nil {
                _ = state.edit(mention, values: ["link": link.id, "recipient": recipient, "author": userID, "created": String(now.timeIntervalSince1970), "read": "false"])
            }
        }
    }
    public func update(_ item: Item, values: [String: String?]) async throws {
        try await store.transaction { state in
            guard let current = state.items[item.key], !current.deleted else { throw ClippingsError.storage("This item has been deleted.") }
            guard state.zones[item.zone.key]?.available != false, state.zones[item.zone.key]?.canWrite != false else { throw ClippingsError.readOnly }
            var values = values
            if let name = values["title"] {
                let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ClippingsError.emptyName }
                values["title"] = try LinkRules.text(trimmed, limit: item.kind == .link ? 500 : 120, label: "Title")
            }
            if let summary = values["summary"] { values["summary"] = try LinkRules.text(summary ?? "", limit: 5_000, label: "Description") }
            if let selection = values["collection"], let selection, !state.visible(.collection, zone: item.zone).contains(where: { $0.id == selection }) {
                throw ClippingsError.validation("This collection no longer exists. Choose another collection.")
            }
            _ = state.edit(current, values: values)
        }
    }
    public func delete(_ item: Item) async throws {
        try await store.transaction { state in
            guard state.zones[item.zone.key]?.canWrite != false else { throw ClippingsError.readOnly }
            if item.kind == .collection {
                for link in state.visible(.link, zone: item.zone) where link["collection"] == item.id {
                    _ = state.edit(link, values: ["collection": nil])
                }
            }
            _ = state.edit(item, values: ["updated": String(Date().timeIntervalSince1970)], delete: true)
        }
    }
    public func saveNote(for link: Item, text: String, userID: String) async throws {
        let text = try LinkRules.text(text, limit: 10_000, label: "Note")
        try await store.transaction { state in
            let note = Item(id: "note-" + link.id, kind: .note, zone: Zone(name: "clippings-personal"))
            _ = state.edit(note, values: ["link": link.key, "text": text, "author": userID])
        }
    }
    public func markRead(_ mention: Item, userID: String) async throws {
        guard mention.kind == .mention, mention["recipient"] == userID else { throw ClippingsError.readOnly }
        try await store.transaction { state in
            let receipt = Item(id: "read-" + mention.id, kind: .receipt, zone: Zone(name: "clippings-personal"))
            _ = state.edit(receipt, values: ["mention": mention.key, "author": userID, "read": "true"])
        }
    }
    static func validateLibrary(_ library: Item, state: Snapshot) throws {
        guard state.items[library.key]?.deleted == false, state.zones[library.zone.key]?.available != false else { throw ClippingsError.missingLibrary }
        guard state.zones[library.zone.key]?.canWrite != false else { throw ClippingsError.readOnly }
    }
}
