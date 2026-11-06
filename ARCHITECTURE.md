# Clippings architecture

Native SwiftUI, iOS 17+, Swift 6 strict concurrency. Three tabs: Library (collections, search, saved links), Mentions (explicit mentions only), and Family (libraries, participants, settings). NavigationSplitView adapts the library to iPad. System typography and SF Symbols, semantic grouped backgrounds, restrained evergreen accent, native forms, sheets and confirmation dialogs.

CloudKit is the shared source of truth. Each family gets a custom record zone in the owner's private database; zone-wide CKShare exposes it in participants' shared databases. Private notes live in a separate unshared zone. No automatic SwiftData/Core Data cloud synchronization is used.

The offline store and outbox will use Apple SQLite with WAL and atomic transactions, shared through an App Group. This deliberately avoids competing SwiftData contexts across the host app and extension. Domain values are Codable, Sendable structs. Every changed field has a Lamport clock and device ID: concurrent edits to distinct fields survive; same-field ties resolve lexicographically by device ID. Tombstones dominate edits. Stable record IDs make retries idempotent. Acknowledgements compare the uploaded snapshot with the current outbox before clearing it.

Layers: `Sources/ClippingsCore` (models, validation, persistence and synchronization), `App/Services` (Apple adapters), `App/Features` (SwiftUI), and `ShareExtension`. Unit tests use injected cloud and notification adapters. They do not validate real CloudKit.

## Synchronization and recovery

`SyncEngine` is an actor with one in-flight run. A run verifies the current account, discovers private/shared zones, provisions only new local owner zones, pulls every change page, uploads the durable outbox, then pulls again. Tokens and fetched items commit in the same SQLite transaction. Tokens only advance after all records in a page sequence decode successfully. Expired tokens trigger a complete refetch; missing previously uploaded records become local tombstones. Pending edits to hard-deleted records are retained in a recovery archive. Missing/revoked zones are hidden and never recreated automatically, and their outbox remains exportable.

The Apple adapter uses change-tag-checked writes, refetches and deterministically merges conflicts, and reuses record IDs on every retry. Errors do not clear queued work. The app retries with bounded exponential backoff, respects CKError retry-after, and refreshes on foreground, pull-to-refresh and network reconnection. A different Apple Account cannot upload the previous account's queue; the UI locks until the original account returns.

The complete versioned domain record is stored as a CloudKit Bytes field. This preserves per-field clocks without dozens of dynamic CloudKit schema fields. Schema versions above the supported version stop synchronization without acknowledging pending work or advancing tokens. Local schema v1 stores optional recovery fields for backward-compatible additive changes. Future non-additive changes must add an explicit transactional migration, keep the original database, and test upgrade/rollback paths before release.

Private notes reference the local canonical library scope/zone/record key and live in `clippings-personal`, which is never shared. Participant identities come from CKShare user record IDs; names are presentation only. Activities and comments are intentionally omitted from v1 because they are not needed for link management or mention delivery.

## Share Extension

The extension reads at most 12 providers, prefers URL attachments, then detects a URL in bounded plain text. It does not crawl or store webpages. Both processes use the same SQLite store and transaction/outbox code. Each presentation has a stable operation ID; canonical URL matching also prevents repeated saves in the same library. Save commits locally first. A foreground synchronization attempt has a ten-second UI budget; early dismissal or process termination leaves the durable queue for the next app/extension sync. No background execution guarantee is assumed. Metadata extraction is kept out of the extension's critical save path.

## Mentions and notifications

Mentions are separate records with stable recipient/author IDs. A local notification is eligible only when the current user is the recipient, is not the author, the link still exists, the mention is unread, and it has not been delivered on this device. A stable request ID plus pending/delivered checks covers reprocessing. Failed or denied notification scheduling does not mark the mention delivered. Read receipts are separate records in the recipient's unshared personal zone, so view-only participants can mark mentions read and another device can remove an obsolete alert after syncing.

Private/shared CKDatabaseSubscriptions send content-available pushes with no alert text, sound or badge. The app fetches changes before deciding whether a local alert is relevant. Foreground notifications are not presented over the UI. A remote-fetch callback is completed once, with a twenty-second deadline; the durable queue does not depend on completion. Opening a notification routes to the cached/synced saved link. Invitations use Apple's native CloudKit sharing delivery, not a separate notification service.

APNs, local notification authorization, background scheduling, user force-quit and network access all affect delivery. A notification can be delayed or absent. Foreground and manual refresh always reconcile unread mentions. There is a narrow cross-service crash window between notification scheduling and the local delivery ledger; stable IDs and delivered-request inspection mitigate it, but no exactly-once delivery guarantee is claimed.

## Preview and cache behavior

Preview fetching starts after the URL transaction commits and times out independently. Apple LinkPresentation metadata (title, image/icon providers) is archived securely for seven days, with an 8 MB per-item and 50 MB total cache budget. The regenerable preview directory is excluded from backup; the database containing unsent user changes is not. An arriving preview cannot overwrite a title the user edited while the request was pending. There is no use of private metadata-description APIs or webpage scraping; descriptions are optional user text. Database files use protection until first unlock so allowed background processing can access the durable queue.

## Accessibility

Native navigation, forms, pickers, menus and tabs retain their system semantics. Collection icons have spoken names, icon-only toolbar actions have labels, and link rows combine their title/domain/date for VoiceOver. Empty states scroll at accessibility text sizes and use shorter explanatory copy without reducing the user's font size. The iPad interface uses NavigationSplitView. Both app and extension adapt the evergreen accent for dark appearance.
