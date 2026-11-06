# Clippings

**Your family’s corner of the internet.**

A native iPhone and iPad app for keeping the links your family wants to come back to. Built with Swift 6, SwiftUI and Apple's CloudKit sharing infrastructure. iOS 17 and later. No Clippings account, custom backend, advertising, subscription or third-party analytics.

## What is implemented

- Family libraries and collections with SF Symbols, native search, sorting, moving and deletion.
- Offline link saving, durable queued changes and a native Share Extension for URLs and captions.
- A newspaper-inspired iPhone library with serif headlines, warm paper/charcoal appearances, and a matching light/dark app icon. The latest five links use photo cards with short excerpts; older links stay compact.
- LinkPresentation thumbnails and titles, bounded local metadata/excerpt caches, domain fallbacks and user-written descriptions. Public article openings are preferred for excerpts, with website descriptions as a fallback.
- Owner/private and participant/shared CloudKit zones, CKShare invitations, native participant management and permissions.
- Deterministic conflict handling, tombstones, expired-token recovery, account isolation and exportable recovery copies.
- Private notes and mention read receipts in an unshared personal zone.
- Explicit mentions when saving a link or from **Mention someone** on a saved link. Any member with editing access can mention the owner or another member. Alerts are filtered and deduplicated, with silent CloudKit subscriptions; foreground refresh recovers changes when background delivery is unavailable.
- Adaptive iPad navigation, light/dark appearance, Dynamic Type, accessibility identifiers, privacy manifests and an original app icon.

## Build and run locally

1. Open `Clippings.xcodeproj` in Xcode 26 or newer.
2. Select the **Clippings** scheme and an installed iPhone or iPad simulator.
3. Run. The default build stores links locally and leaves iCloud disabled until you configure your own Apple Developer resources.

No external packages are required. The committed Xcode project includes the app, Share Extension, unit-test and UI-test targets. Do not use a web server: this is a native iOS app.

The app, project and main scheme are named **Clippings**. This is a fresh app identity: `app.clippings.family`, with its own Share Extension, App Group, CloudKit container and storage names. No compatibility aliases or data migration are included.

For real family sharing, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, enter your registered team/bundle/container/group values, enable cloud access, and follow [CLOUDKIT_SETUP.md](CLOUDKIT_SETUP.md). That local file is ignored by Git. Both app and extension must be provisioned for the same App Group and CloudKit container.

## Tests

```sh
swift test
xcodebuild test -project Clippings.xcodeproj -scheme Clippings \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Use `python3 scripts/select_simulator.py` to find an installed simulator ID if that name is unavailable. GitHub Actions runs core, simulator unit and UI tests on pushes to main and pull requests, without production certificates. See [TESTING.md](TESTING.md) for verification results and the repeatable two-account device procedure.

If your checkout is in an iCloud-synced Desktop folder, choose **Keep Downloaded** in Finder and put build output outside Desktop. [DEVELOPMENT.md](DEVELOPMENT.md) explains the temporary validation-copy helper.

## Verification boundary

Local features and synchronization logic have automated coverage. **Real multi-account CloudKit, signed App Group sharing, APNs delivery and App Store distribution have not been verified in a configured Apple environment.** The native integrations are implemented, but those checks remain required before release. The iOS 17 deployment target compiles against the installed current SDK; minimum-version device/runtime behavior still needs the release matrix in TESTING.md.

CloudKit does not promise immediate synchronization or background delivery. Swiping Clippings closed prevents its silent CloudKit updates until the app is reopened; see [Apple’s subscription delivery guidance](https://developer.apple.com/library/archive/qa/qa1917/_index.html). With notification permission, explicit mentions can show an alert while the app is open as well as in the background. Ordinary link activity never requests an alert. Private notes stay out of shared family zones. Title/image previews use public LinkPresentation APIs. Excerpts use a separate, bounded HTML request without persistent cookies: the first two sentences from article/main paragraphs, or page description metadata when article text is unavailable. Script-rendered and restricted pages may have no excerpt or image. User descriptions take precedence and are never overwritten by fetched text. Preview failures never prevent saving or opening a link.

## Project guide

- `Sources/ClippingsCore`: domain values, validation, SQLite transactions, outbox, sync engine and mention processing.
- `App`: SwiftUI features, design assets and Apple service adapters.
- `ShareExtension`: native share UI and attachment processing.
- `Tests` / `UITests`: deterministic domain/integration doubles and XCUITest.
- `Config`: entitlements, Info.plists and configuration examples.
- `scripts`: deterministic project/icon generation and simulator/validation helpers.

Read [ARCHITECTURE.md](ARCHITECTURE.md), [DEVELOPMENT.md](DEVELOPMENT.md), [CLOUDKIT_SETUP.md](CLOUDKIT_SETUP.md), [TESTING.md](TESTING.md) and [CHANGELOG.md](CHANGELOG.md) for details.
