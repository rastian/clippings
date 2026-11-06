# linkin architecture

Native SwiftUI, iOS 17+, Swift 6 strict concurrency. Three tabs: Library (collections, search, saved links), Mentions (explicit mentions only), and Family (libraries, participants, settings). NavigationSplitView adapts the library to iPad. System typography and SF Symbols, semantic grouped backgrounds, restrained evergreen accent, native forms, sheets and confirmation dialogs.

CloudKit is the shared source of truth. Each family gets a custom record zone in the owner's private database; zone-wide CKShare exposes it in participants' shared databases. Private notes live in a separate unshared zone. No automatic SwiftData/Core Data cloud synchronization is used.

The offline store and outbox will use Apple SQLite with WAL and atomic transactions, shared through an App Group. This deliberately avoids competing SwiftData contexts across the host app and extension. Domain values are Codable, Sendable structs. Every changed field has a Lamport clock and device ID: concurrent edits to distinct fields survive; same-field ties resolve lexicographically by device ID. Tombstones dominate edits. Stable record IDs make retries idempotent. Acknowledgements compare the uploaded snapshot with the current outbox before clearing it.

Layers: `Sources/LinkinCore` (models, validation, persistence and synchronization), `App/Services` (Apple adapters), `App/Features` (SwiftUI), and `ShareExtension`. Unit tests use injected cloud and notification adapters. They do not validate real CloudKit.
