# Changelog

## 1.0.0 — in development
- Foundation: native Xcode project, Swift 6 domain, deterministic conflicts and URL validation, initial tests and macOS CI.
- Local app: durable SQLite store and outbox, library and collection management, URL saving, search and sorting, private notes, cached LinkPresentation previews, adaptive native navigation and original app icon.
- Sharing: manual CloudKit synchronization, zone-wide private CKShare, native participant management and invitation acceptance, permissions, account isolation, change-token recovery and recoverable conflict archives.
- Share Extension: URL and caption parsing, library/collection/member selection, durable idempotent saves and a bounded foreground iCloud attempt with explicit offline status.
- Mentions: silent CloudKit subscriptions, explicit recipient filtering, private read receipts, notification deduplication and deep links, foreground recovery, and user-controlled alert permission.
- Quality: two-account sharing simulation, paginated-fetch recovery, native attachment-provider and preview-failure integration tests, broader UI coverage, large-text scrolling, iPad configuration, dark-mode polish, privacy manifests and release/setup documentation.
