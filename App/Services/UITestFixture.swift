#if DEBUG
import Foundation

extension Configuration {
    /// Isolated, local-only fixtures for testing the invited member’s interface.
    static func resetUITestStore(_ store: LocalStore) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard isUITesting, arguments.contains("--reset") else { return }
        let sharedLibrary = arguments.contains("--shared-library")
        let readOnly = arguments.contains("--read-only")
        let missingOwner = arguments.contains("--missing-owner")
        try await store.transaction { state in
            state = Snapshot()
            guard sharedLibrary else { return }
            state.accountID = "participant"
            let zone = Zone(name: "clippings-family-ui-test", owner: "owner", scope: .shared)
            _ = state.edit(Item(id: "family", kind: .library, zone: zone), values: ["title": "Our family", "owner": "owner"])
            _ = state.edit(Item(id: "pasta", kind: .link, zone: zone), values: [
                "title": "Weekend pasta", "url": "https://example.com/pasta", "domain": "example.com", "author": "owner",
                "created": String(Date().timeIntervalSince1970),
                "summary": "A few good tomatoes and a little patience make a meal worth sharing. Bring everyone to the table for a slow Sunday lunch."
            ])
            state.zones[zone.key]?.members = [
                Member(id: "owner", name: "Alex", role: "Owner", canWrite: true),
                Member(id: "participant", name: "Sam", role: "Member", canWrite: !readOnly)
            ]
            state.zones[zone.key]?.canWrite = !readOnly
            if missingOwner { state.zones[zone.key]?.members.removeAll { $0.id == "owner" } }
            state.pending = [:]
        }
    }
}
#endif
