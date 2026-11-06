# Apple Developer and CloudKit setup

**Not configured or verified in a real iCloud environment.** The unsigned local build deliberately leaves cloud access disabled. No production keys, provisioning profiles or Apple Account details belong in this repository.

1. In your Apple Developer team, register the main App ID (`app.clippings.family`) and extension App ID (`app.clippings.family.share`), or replace these with your own unique identifiers. Enable iCloud/CloudKit and App Groups for both, and Push Notifications for the host.
2. Register an iCloud container (default `iCloud.app.clippings.family`) and an App Group (default `group.app.clippings.family`). Associate both App IDs with both resources. A shared App Group is essential: the extension and app must use the same queue.
3. Create ignored `Config/Local.xcconfig` with your `DEVELOPMENT_TEAM`, `CLIPPINGS_CONTAINER`, `CLIPPINGS_APP_GROUP`, and `CLIPPINGS_CLOUD_ENABLED = YES`. Set `CLIPPINGS_BUNDLE_ID` to customize the main identifier; extension and test identifiers derive from it automatically. Select the team and automatic signing for both targets in Xcode.
4. Use Development provisioning initially. The host needs `aps-environment`, iCloud container identifiers, CloudKit service, App Groups and the remote-notification background mode. The extension needs the same container/group, but no remote-notification background mode. App Info.plist includes CKSharingSupported and handles both scene and application invitation callbacks.
5. Run on a device signed into an Apple Account with iCloud Drive enabled. Create a library, refresh, and verify a `clippings-family-<UUID>` custom zone in the private database. A separate unshared `clippings-personal` zone is created only when private notes/receipts need it.
6. CloudKit's Development schema creates `ClippingsItem` with `payload` (Bytes), `kind` (String), `schemaVersion` (Int64). No query indexes are required: synchronization uses zone changes, not record queries. A payload contains the versioned domain item and per-field clocks. CKShare uses Apple's built-in record type.
7. Invite a second Apple Account with **Invite & manage family**. Public access is disabled. The native controller supports private invitations, read-only/read-write participants, participant removal and stopping sharing. Invitees accept through Messages/Mail; their accepted zones appear in the shared database.
8. Before TestFlight, deploy the schema to Production in CloudKit Console. TestFlight uses Production; a Development build cannot see its data. Configure distribution signing/APNs and repeat the complete two-account procedure in TESTING.md against Production.

## Current SDK references

Reviewed on 6 November 2026 against the installed Xcode 26.6 SDK and Apple's documentation:

- [Shared records](https://developer.apple.com/documentation/cloudkit/shared-records): private owner zones, shared participant databases, CKSharingSupported, invitation acceptance and leaving shares.
- [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare): zone-wide sharing and record hierarchies.
- [CKFetchRecordZoneChangesOperation](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation): zone change tokens, paging and deletions. Implementation uses the SDK's async `recordZoneChanges(inZoneWith:since:)` equivalent (available since iOS 15).
- [CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription): private/shared subscriptions and best-effort background notifications.

Do not enable SwiftData automatic CloudKit synchronization or NSPersistentCloudKitContainer alongside this manual engine. CloudKit sharing does not create a family storage bucket; the owner hosts the original zone. There is no custom backend, shared subscription, or app account.

## Distribution privacy

The app and extension include a privacy manifest declaring no tracking or developer data collection. Local preview-cache file metadata uses Apple's [C617.1 reason for files in app and App Group containers](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons). Review the archive's privacy report and App Store Connect disclosures before submission, particularly if adding dependencies or data collection. Links are stored in the user's iCloud and explicitly shared with selected participants; fetching a preview contacts that link's website.
