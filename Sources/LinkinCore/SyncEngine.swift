import Foundation

public struct ChangePage: Sendable {
    public var items: [Item]
    public var deletedIDs: [String]
    public var token: Data
    public var moreComing: Bool
    public init(items: [Item], deletedIDs: [String] = [], token: Data, moreComing: Bool = false) {
        self.items = items; self.deletedIDs = deletedIDs; self.token = token; self.moreComing = moreComing
    }
}
public enum SyncFailure: Error, Sendable { case expiredToken, retryLater, removedRecord }
public protocol CloudRepository: Sendable {
    func currentUserID() async throws -> String
    func listZones() async throws -> [ZoneState]
    func createZone(_ zone: Zone) async throws
    func changes(in zone: Zone, since token: Data?) async throws -> ChangePage
    func save(_ item: Item, wasUploaded: Bool) async throws -> Item
    func remove(_ zone: Zone) async throws
}

public actor SyncEngine {
    private let store: LocalStore
    private let cloud: any CloudRepository
    private var running: Task<Void, Error>?
    public init(store: LocalStore, cloud: any CloudRepository) { self.store = store; self.cloud = cloud }
    public func synchronize() async throws {
        if let running { return try await running.value }
        let task = Task { try await self.run() }
        running = task
        defer { running = nil }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func run() async throws {
        let user = try await cloud.currentUserID()
        try await store.transaction { state in
            if let previous = state.accountID, previous != user { throw LinkinError.accountChanged }
            if state.accountID == nil {
                state.accountID = user
                for item in Array(state.items.values) {
                    var values: [String: String?] = [:]
                    for key in ["author", "owner", "recipient"] where item[key] == "local-user" { values[key] = user }
                    if !values.isEmpty { _ = state.edit(item, values: values) }
                }
            }
        }
        // Enumerating both databases also recovers from dropped database pushes and revocations.
        let remoteZones = try await cloud.listZones()
        let remoteKeys = Set(remoteZones.map { $0.zone.key })
        let initial = try await store.read()
        for zone in initial.zones.values where !remoteKeys.contains(zone.zone.key) && zone.zone.scope == .owned && initial.settings["known:\(zone.zone.key)"] == nil && initial.settings["remove:\(zone.zone.key)"] == nil {
            try await cloud.createZone(zone.zone)
        }
        try await store.transaction { state in
            for var zone in remoteZones {
                zone.token = state.zones[zone.zone.key]?.token
                state.zones[zone.zone.key] = zone
                state.settings["known:\(zone.zone.key)"] = "true"
            }
            for (key, zone) in state.zones where !remoteKeys.contains(key) && state.settings["known:\(key)"] != nil {
                var missing = zone; missing.available = false; state.zones[key] = missing
            }
        }
        let snapshot = try await store.read()
        for zoneState in snapshot.zones.values.sorted(by: { $0.zone.key < $1.zone.key }) {
            let zone = zoneState.zone
            if snapshot.settings["remove:\(zone.key)"] != nil {
                try await cloud.remove(zone)
                try await store.transaction { state in
                    state.items = state.items.filter { $0.value.zone != zone }
                    state.pending = state.pending.filter { $0.value.zone != zone }
                    state.zones.removeValue(forKey: zone.key)
                    state.settings.removeValue(forKey: "remove:\(zone.key)")
                    state.settings.removeValue(forKey: "known:\(zone.key)")
                }
                continue
            }
            guard zoneState.available else { continue }
            try Task.checkCancellation()
            try await fetch(zone, token: zoneState.token)
            // More than one pass drains edits queued while an upload is in flight.
            for _ in 0..<3 {
                let current = try await store.read()
                let queued = current.pending.values.filter { $0.zone == zone }.sorted { $0.id < $1.id }
                guard !queued.isEmpty, current.zones[zone.key]?.canWrite != false else { break }
                for item in queued {
                    try Task.checkCancellation()
                    do {
                        let saved = try await cloud.save(item, wasUploaded: current.settings["uploaded:\(item.key)"] == "true")
                        try await store.transaction { state in
                            try state.acknowledge(item, saved: saved)
                            state.settings["uploaded:\(item.key)"] = "true"
                        }
                    } catch SyncFailure.removedRecord {
                        try await store.transaction { Self.recordDeleted(item.id, zone: zone, state: &$0) }
                    }
                }
            }
            try await fetch(zone, token: (try await store.read()).zones[zone.key]?.token)
        }
    }
    private func fetch(_ zone: Zone, token original: Data?) async throws {
        var token = original
        var reset = original == nil
        var items: [Item] = []
        var deleted: [String] = []
        var hasMore = true
        while hasMore {
            do {
                let page = try await cloud.changes(in: zone, since: token)
                items.append(contentsOf: page.items); deleted.append(contentsOf: page.deletedIDs)
                token = page.token; hasMore = page.moreComing
            } catch SyncFailure.expiredToken {
                guard !reset else { throw SyncFailure.expiredToken }
                reset = true; token = nil; items = []; deleted = []
            }
        }
        let fetched = items, removals = deleted, finalToken = token, isFullFetch = reset
        try await store.transaction { state in
            let fetchedIDs = Set(fetched.map(\.id))
            if isFullFetch {
                for item in Array(state.items.values) where item.zone == zone && !fetchedIDs.contains(item.id) && state.settings["uploaded:\(item.key)"] == "true" {
                    Self.recordDeleted(item.id, zone: zone, state: &state)
                }
            }
            for item in fetched {
                try state.receive(item)
                state.settings["uploaded:\(item.key)"] = "true"
            }
            for id in removals { Self.recordDeleted(id, zone: zone, state: &state) }
            if state.zones[zone.key] == nil { state.zones[zone.key] = ZoneState(zone: zone) }
            state.zones[zone.key]?.token = finalToken
            state.settings["known:\(zone.key)"] = "true"
        }
    }
    private static func recordDeleted(_ id: String, zone: Zone, state: inout Snapshot) {
        let key = "\(zone.key)|\(id)"
        if let pending = state.pending.removeValue(forKey: key) {
            // Keep unsent work in a recoverable archive rather than resurrecting server deletions.
            state.recovered = state.recovered ?? [:]; state.recovered?[key] = pending
        }
        state.items[key]?.deleted = true
    }
}
