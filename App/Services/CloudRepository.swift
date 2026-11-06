import CloudKit
import Foundation

struct AppleCloudRepository: CloudRepository {
    let container: CKContainer
    init(containerID: String = Configuration.containerID) { container = CKContainer(identifier: containerID) }
    func database(_ zone: Zone) -> CKDatabase { zone.scope == .owned ? container.privateCloudDatabase : container.sharedCloudDatabase }
    func currentUserID() async throws -> String {
        switch try await container.accountStatus() {
        case .available: return try await container.userRecordID().recordName
        case .noAccount: throw ClippingsError.cloud("Sign in to iCloud in Settings to share with your family. Your saved links are still on this device.")
        case .restricted: throw ClippingsError.cloud("iCloud access is restricted on this device. Check your device or family restrictions.")
        case .temporarilyUnavailable, .couldNotDetermine: throw ClippingsError.cloud("iCloud is temporarily unavailable. Your changes are saved and will retry.")
        @unknown default: throw ClippingsError.cloud("iCloud is unavailable. Please try again later.")
        }
    }
    func listZones() async throws -> [ZoneState] {
        var result: [ZoneState] = []
        for scope in [DatabaseScope.owned, .shared] {
            let database = scope == .owned ? container.privateCloudDatabase : container.sharedCloudDatabase
            for remote in try await database.allRecordZones() where remote.zoneID.zoneName.hasPrefix("clippings-family-") || (scope == .owned && remote.zoneID.zoneName == "clippings-personal") {
                let zone = Zone(name: remote.zoneID.zoneName, owner: scope == .owned ? "__defaultOwner__" : remote.zoneID.ownerName, scope: scope)
                var state = ZoneState(zone: zone)
                if let shareReference = remote.share {
                    guard let share = try await database.record(for: shareReference.recordID) as? CKShare else { throw ClippingsError.cloud("The family sharing information could not be read.") }
                    state.members = share.participants.compactMap { participant in
                        guard let id = participant.userIdentity.userRecordID?.recordName else { return nil }
                        let name = participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? "Family member"
                        let role = participant.role == .owner ? "Owner" : participant.acceptanceStatus == .accepted ? "Member" : "Invited"
                        return Member(id: id, name: name.isEmpty ? "Family member" : name, role: role, canWrite: participant.permission == .readWrite || participant.role == .owner)
                    }
                    state.canWrite = scope == .owned || share.currentUserParticipant?.permission == .readWrite
                }
                result.append(state)
            }
        }
        return result
    }
    func createZone(_ zone: Zone) async throws {
        guard zone.scope == .owned else { throw ClippingsError.readOnly }
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: RecordCodec.zoneID(zone)))
    }
    func changes(in zone: Zone, since token: Data?) async throws -> ChangePage {
        do {
            let page = try await database(zone).recordZoneChanges(inZoneWith: RecordCodec.zoneID(zone), since: RecordCodec.token(token))
            var items: [Item] = []
            for value in page.modificationResultsByID.values {
                let record = try value.get().record
                if record.recordType == RecordCodec.recordType { items.append(try RecordCodec.decode(record, zone: zone)) }
            }
            return ChangePage(items: items, deletedIDs: page.deletions.filter { $0.recordType == RecordCodec.recordType }.map { $0.recordID.recordName }, token: try RecordCodec.tokenData(page.changeToken), moreComing: page.moreComing)
        } catch let error as CKError where error.code == .changeTokenExpired { throw SyncFailure.expiredToken }
    }
    func save(_ item: Item, wasUploaded: Bool) async throws -> Item {
        let database = database(item.zone)
        let id = CKRecord.ID(recordName: item.id, zoneID: RecordCodec.zoneID(item.zone))
        // Refetching supplies the server change tag and makes cross-process retries safe.
        for _ in 0..<5 {
            var record: CKRecord
            var merged = item
            do {
                record = try await database.record(for: id)
                merged = try item.merging(RecordCodec.decode(record, zone: item.zone))
            } catch let error as CKError where error.code == .unknownItem {
                if wasUploaded { throw SyncFailure.removedRecord }
                record = CKRecord(recordType: RecordCodec.recordType, recordID: id)
            }
            try RecordCodec.apply(merged, to: record)
            do {
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                guard let saved = result.saveResults[id] else { throw ClippingsError.cloud("iCloud did not confirm this save. It will be retried.") }
                return try RecordCodec.decode(saved.get(), zone: item.zone)
            } catch let error as CKError where error.code == .serverRecordChanged { continue }
        }
        throw SyncFailure.retryLater
    }
    func remove(_ zone: Zone) async throws {
        do {
            if zone.scope == .owned { _ = try await database(zone).deleteRecordZone(withID: RecordCodec.zoneID(zone)) }
            else {
                let remote = try await database(zone).recordZone(for: RecordCodec.zoneID(zone))
                guard let share = remote.share else { return }
                _ = try await database(zone).deleteRecord(withID: share.recordID)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem { return }
    }
    func sharingRecord(for library: Item) async throws -> CKShare {
        let database = database(library.zone)
        let zone = try await database.recordZone(for: RecordCodec.zoneID(library.zone))
        if let ref = zone.share, let share = try await database.record(for: ref.recordID) as? CKShare { return share }
        guard library.zone.scope == .owned else { throw ClippingsError.readOnly }
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = library.title as CKRecordValue
        share.publicPermission = .none
        do { return try await database.save(share) as? CKShare ?? share }
        catch let error as CKError where error.code == .serverRecordChanged {
            let refreshed = try await database.recordZone(for: zone.zoneID)
            guard let reference = refreshed.share, let existing = try await database.record(for: reference.recordID) as? CKShare else { throw error }
            return existing
        }
    }
    func accept(_ metadata: CKShare.Metadata, boundAccount: String?) async throws {
        let user = try await currentUserID()
        try InvitationRules.validate(container: metadata.containerIdentifier, expected: container.containerIdentifier ?? "", currentUser: user, boundUser: boundAccount)
        let result = try await container.accept([metadata])
        guard let accepted = result[metadata] else { throw ClippingsError.cloud("iCloud did not confirm your invitation. Try opening it again.") }
        _ = try accepted.get()
    }
}
