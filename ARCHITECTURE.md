# linkin architecture

Native SwiftUI, iOS 17+, Swift 6 strict concurrency. Three tabs: Library (collections, search, saved links), Mentions (explicit mentions only), and Family (libraries, participants, settings). NavigationSplitView adapts the library to iPad. System typography and SF Symbols, semantic grouped backgrounds, restrained evergreen accent, native forms, sheets and confirmation dialogs.

CloudKit is the shared source of truth. Each family gets a custom record zone in the owner's private database; zone-wide CKShare exposes it in participants' shared databases. Private notes live in a separate unshared zone. No automatic SwiftData/Core Data cloud synchronization is used.

The offline store and outbox will use Apple SQLite with WAL and atomic transactions, shared through an App Group. This deliberately avoids competing SwiftData contexts across the host app and extension. Domain values are Codable, Sendable structs. Every changed field has a Lamport clock and device ID: concurrent edits to distinct fields survive; same-field ties resolve lexicographically by device ID. Tombstones dominate edits. Stable record IDs make retries idempotent. Acknowledgements compare the uploaded snapshot with the current outbox before clearing it.

Layers: `Sources/LinkinCore` (models, validation, persistence and synchronization), `App/Services` (Apple adapters), `App/Features` (SwiftUI), and `ShareExtension`. Unit tests use injected cloud and notification adapters. They do not validate real CloudKit.

## Synchronization and recovery

`SyncEngine` is an actor with one in-flight run. A run verifies the current account, discovers private/shared zones, provisions only new local owner zones, pulls every change page, uploads the durable outbox, then pulls again. Tokens and fetched items commit in the same SQLite transaction. Tokens only advance after all records in a page sequence decode successfully. Expired tokens trigger a complete refetch; missing previously uploaded records become local tombstones. Pending edits to hard-deleted records are retained in a recovery archive. Missing/revoked zones are hidden and never recreated automatically, and their outbox remains exportable.

The Apple adapter uses change-tag-checked writes, refetches and deterministically merges conflicts, and reuses record IDs on every retry. Errors do not clear queued work. The app retries with bounded exponential backoff, respects CKError retry-after, and refreshes on foreground, pull-to-refresh and network reconnection. A different Apple Account cannot upload the previous account's queue; the UI locks until the original account returns.

The complete versioned domain record is stored as a CloudKit Bytes field. This preserves per-field clocks without dozens of dynamic CloudKit schema fields. Schema versions above the supported version stop synchronization without acknowledging pending work or advancing tokens. Local schema v1 stores optional recovery fields for backward-compatible additive changes. Future non-additive changes must add an explicit transactional migration, keep the original database, and test upgrade/rollback paths before release.

Private notes reference the local canonical library scope/zone/record key and live in `linkin-personal`, which is never shared. Participant identities come from CKShare user record IDs; names are presentation only. Activities and comments are intentionally omitted from v1 because they are not needed for link management or mention delivery.
