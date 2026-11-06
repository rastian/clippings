import Foundation

public enum ClippingsError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL, emptyName, missingLibrary, readOnly, incompatibleSchema, accountChanged
    case storage(String), cloud(String), validation(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a complete http or https website address."
        case .emptyName: "Please enter a name."
        case .missingLibrary: "Choose an available family library."
        case .readOnly: "You have view-only access to this library."
        case .incompatibleSchema: "This library needs a newer version of Clippings. Please update the app."
        case .accountChanged: "Your iCloud account changed. Your previous account’s pending changes are preserved on this device. Sign back in to sync them."
        case .storage(let message), .cloud(let message), .validation(let message): message
        }
    }
}

public enum RecordKind: String, Codable, Sendable { case library, collection, link, mention, note, receipt }
public enum DatabaseScope: String, Codable, Sendable { case owned, shared }
public struct Zone: Codable, Hashable, Sendable {
    public var name: String
    public var owner: String
    public var scope: DatabaseScope
    public init(name: String, owner: String = "__defaultOwner__", scope: DatabaseScope = .owned) {
        self.name = name; self.owner = owner; self.scope = scope
    }
    public var key: String { "\(scope.rawValue)|\(owner)|\(name)" }
}

/// Lamport clocks avoid wall-clock skew. Actor IDs break ties consistently on every device.
public struct Field: Codable, Equatable, Sendable {
    public var value: String?
    public var clock: Int64
    public var actor: String
    public init(_ value: String?, clock: Int64, actor: String) {
        self.value = value; self.clock = clock; self.actor = actor
    }
    func wins(over other: Field) -> Bool {
        clock == other.clock ? actor > other.actor : clock > other.clock
    }
}

public struct Item: Codable, Identifiable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var id: String
    public var kind: RecordKind
    public var zone: Zone
    public var fields: [String: Field]
    public var deleted: Bool
    public var schema: Int
    public init(id: String = UUID().uuidString, kind: RecordKind, zone: Zone, fields: [String: Field] = [:], deleted: Bool = false) {
        self.id = id; self.kind = kind; self.zone = zone; self.fields = fields
        self.deleted = deleted; schema = Self.schemaVersion
    }
    public subscript(_ key: String) -> String { fields[key]?.value ?? "" }
    public var title: String { self["title"] }
    public var date: Date { Date(timeIntervalSince1970: Double(self["created"]) ?? 0) }
    public var revision: Int64 { fields.values.map(\.clock).max() ?? 0 }
    public var key: String { "\(zone.key)|\(id)" }
    public func merging(_ remote: Item) throws -> Item {
        guard schema <= Self.schemaVersion, remote.schema <= Self.schemaVersion else { throw ClippingsError.incompatibleSchema }
        guard id == remote.id, kind == remote.kind else { throw ClippingsError.storage("Invalid record identity.") }
        var result = self
        for (key, field) in remote.fields {
            if result.fields[key].map({ field.wins(over: $0) }) ?? true { result.fields[key] = field }
        }
        // Tombstones are permanent: an offline edit must never resurrect a deleted item.
        result.deleted = deleted || remote.deleted
        return result
    }
}

public struct Member: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    public var canWrite: Bool
    public init(id: String, name: String, role: String, canWrite: Bool) {
        self.id = id; self.name = name; self.role = role; self.canWrite = canWrite
    }
}
public struct ZoneState: Codable, Equatable, Sendable {
    public var zone: Zone
    public var token: Data?
    public var available: Bool = true
    public var canWrite: Bool = true
    public var members: [Member] = []
    public init(zone: Zone) { self.zone = zone }
    /// A shared zone's owner is an addressable member even when cached participant
    /// metadata is incomplete. This does not change the current user's permissions.
    public var libraryMembers: [Member] {
        guard available else { return [] }
        var result = members.filter { !$0.id.isEmpty && $0.id != "__defaultOwner__" }
        if zone.scope == .shared, !zone.owner.isEmpty, zone.owner != "__defaultOwner__",
           !result.contains(where: { $0.id == zone.owner }) {
            result.insert(Member(id: zone.owner, name: "Library owner", role: "Owner", canWrite: true), at: 0)
        }
        return result
    }
}

public struct Snapshot: Codable, Sendable {
    public var version = 1
    public var actor = UUID().uuidString
    public var clock: Int64 = 0
    public var accountID: String?
    public var items: [String: Item] = [:]
    public var pending: [String: Item] = [:]
    public var zones: [String: ZoneState] = [:]
    public var recovered: [String: Item]? = [:]
    public var notified: Set<String> = []
    public var settings: [String: String] = [:]
    public init() {}
    public var libraries: [Item] { visible(.library).sorted { $0.date < $1.date } }
    public func visible(_ kind: RecordKind, zone: Zone? = nil) -> [Item] {
        items.values.filter { !$0.deleted && $0.kind == kind && (zone == nil || $0.zone == zone) && zones[$0.zone.key]?.available != false }
    }
    public mutating func edit(_ item: Item, values: [String: String?], delete: Bool = false) -> Item {
        var changed = items[item.key] ?? item
        clock = max(clock, changed.revision) + 1
        for (key, value) in values { changed.fields[key] = Field(value, clock: clock, actor: actor) }
        changed.deleted = changed.deleted || delete
        items[changed.key] = changed; pending[changed.key] = changed
        if zones[changed.zone.key] == nil { zones[changed.zone.key] = ZoneState(zone: changed.zone) }
        return changed
    }
    public mutating func receive(_ remote: Item) throws {
        let merged = try items[remote.key]?.merging(remote) ?? remote
        guard remote.schema <= Item.schemaVersion else { throw ClippingsError.incompatibleSchema }
        if let queued = pending[remote.key], queued.fields.contains(where: { key, field in
            field.actor == actor && field.clock == queued.revision && merged.fields[key]?.value != field.value
        }) {
            recovered = recovered ?? [:]; recovered?[queued.key] = queued
        }
        items[remote.key] = merged; clock = max(clock, merged.revision)
        if pending[remote.key] != nil { pending[remote.key] = merged }
    }
    public mutating func acknowledge(_ sent: Item, saved: Item) throws {
        // An edit made during an upload must stay in the outbox.
        if sent.fields.contains(where: { key, field in
            field.actor == actor && field.clock == sent.revision && saved.fields[key]?.value != field.value
        }) { recovered = recovered ?? [:]; recovered?[sent.key] = sent }
        if pending[sent.key] == sent { pending.removeValue(forKey: sent.key) }
        try receive(saved)
    }
}
