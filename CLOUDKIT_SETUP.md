# Apple Developer and CloudKit setup

**Not configured or verified in a real iCloud environment.** The unsigned local build deliberately leaves cloud access disabled. No production keys, provisioning profiles or Apple Account details belong in this repository.

1. In your Apple Developer team, register the main App ID (`app.linkin.family`) and extension App ID (`app.linkin.family.share`), or replace these with your own unique identifiers. Enable iCloud/CloudKit and App Groups for both, and Push Notifications for the host.
2. Register an iCloud container (default `iCloud.app.linkin.family`) and an App Group (default `group.app.linkin.family`). Associate both App IDs with both resources. A shared App Group is essential: the extension and app must use the same queue.
3. Create ignored `Config/Local.xcconfig` with your `DEVELOPMENT_TEAM`, `LINKIN_CONTAINER`, `LINKIN_APP_GROUP`, and `LINKIN_CLOUD_ENABLED = YES`. If changing bundle IDs, also update the extension's PRODUCT_BUNDLE_IDENTIFIER in `scripts/generate_project.py` and regenerate the project. Select the team and automatic signing for both targets in Xcode.
4. Use Development provisioning initially. The host needs `aps-environment`, iCloud container identifiers, CloudKit service, App Groups and the remote-notification background mode. The extension needs the same container/group, but no remote-notification background mode. App Info.plist includes CKSharingSupported and handles both scene and application invitation callbacks.
5. Run on a device signed into an Apple Account with iCloud Drive enabled. Create a library, refresh, and verify a `linkin-family-<UUID>` custom zone in the private database. A separate unshared `linkin-personal` zone is created only when private notes/receipts need it.
6. CloudKit's Development schema creates `LinkinItem` with `payload` (Bytes), `kind` (String), `schemaVersion` (Int64). No query indexes are required: synchronization uses zone changes, not record queries. A payload contains the versioned domain item and per-field clocks. CKShare uses Apple's built-in record type.
7. Invite a second Apple Account with **Invite & manage family**. Public access is disabled. The native controller supports private invitations, read-only/read-write participants, participant removal and stopping sharing. Invitees accept through Messages/Mail; their accepted zones appear in the shared database.
8. Before TestFlight, deploy the schema to Production in CloudKit Console. TestFlight uses Production; a Development build cannot see its data. Configure distribution signing/APNs and repeat the complete two-account procedure in TESTING.md against Production.

## Current SDK references

Reviewed on 6 November 2026 against the installed Xcode 26.6 SDK and Apple's documentation:

- [Shared records](https://developer.apple.com/documentation/cloudkit/shared-records): private owner zones, shared participant databases, CKSharingSupported, invitation acceptance and leaving shares.
- [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare): zone-wide sharing and record hierarchies.
- [CKFetchRecordZoneChangesOperation](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation): zone change tokens, paging and deletions. Implementation uses the SDK's async `recordZoneChanges(inZoneWith:since:)` equivalent (available since iOS 15).
- [CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription): private/shared subscriptions and best-effort background notifications.

Do not enable SwiftData automatic CloudKit synchronization or NSPersistentCloudKitContainer alongside this manual engine. CloudKit sharing does not create a family storage bucket; the owner hosts the original zone. There is no custom backend, shared subscription, or app account.
