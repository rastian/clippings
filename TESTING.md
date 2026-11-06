# Testing

## Automated tests

- `swift test`: domain and transactional SQLite tests; no account, network or credentials.
- `xcodebuild test -project linkin.xcodeproj -scheme linkin -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`: simulator-hosted unit tests and XCUITest.
- `python3 scripts/select_simulator.py`: prints a destination ID for an installed iPhone simulator.

Tests use isolated temporary databases and controlled timestamps. The two-connection persistence test models concurrent app/extension access. UI tests start from a dedicated empty store; ordinary user data is not reset.

GitHub Actions runs these suites on macOS on pull requests and pushes to main. It selects an installed Xcode 26 and simulator and uploads the result bundle, including failure details. It does not use production signing credentials. No automated test should be described as proof of real multi-account iCloud synchronization.

## Verification record

Foundation: simulator build succeeded; 5 domain tests passed.
Local application: 9 domain/persistence tests passed. All 3 iPhone UI scenarios passed (onboarding/collection/link saving, invalid URL, tabs and empty mentions).

Sharing milestone: 15 core tests passed, including controlled offline/expiry/revocation/account-switch scenarios; 17 iOS unit tests passed including CloudKit record mapping. All 3 UI scenarios passed after adding the sharing lifecycle (the Family test scrolls to the expanded settings footer). Real CloudKit remains unverified until the configuration and two-account device procedure are completed.

Share Extension milestone: app and embedded extension build passed with Swift 6 strict concurrency; all 16 portable tests passed, including URL/caption extraction and unsupported-content cases. Real Safari/YouTube/Instagram/Reddit share-sheet testing needs the signed App Group build; the unsigned build cannot prove cross-process entitlement access.

Notification milestone: all 23 iOS unit tests passed, including five notification/read-receipt tests; the app and extension compile without Swift concurrency warnings. These tests exercise controlled notification adapters, not APNs delivery.

Quality milestone, 6 November 2026 (Xcode 26.6, iOS 26.5 simulator):

- **32 iOS unit/integration tests passed**, including native CloudKit mapping, URL/text item providers, metadata failure, paginated synchronization, account changes during upload, recovery exports and the two-account test double.
- **All 7 iPhone UI scenarios passed** across the full suite and focused fix verification: onboarding/collections/saving, invalid URL, tabs/mentions, search/private notes/move/delete, collection deletion retaining links, persistence across launches, and largest Dynamic Type. The accessibility test taps the visible add button and verifies the editor opens.
- **2 iPad UI scenarios passed in dark mode**: onboarding/collections/saving and largest Dynamic Type. Inspected actual simulator captures of the split view and accessible empty state in [docs/screenshots](docs/screenshots).
- **Unsigned Release builds passed** for the app and embedded Share Extension against the physical-device SDK. This is compilation validation, not a signed archive or distribution test.
- Search over 2,000 links and 2,000 notes averaged about 22–26 ms in local tests. This is a controlled search measurement, not a real-device cloud or storage-throughput claim.
- Info.plists, entitlements and privacy manifests passed property-list validation. No Swift concurrency warnings remained.

The notification milestone also passed GitHub Actions on macOS: [run 42197241470](https://github.com/rastian/linkin/actions/runs/42197241470). The quality commit triggers the expanded suites; the repository's Actions page is the authority for that commit's result. The portable suite contains 27 tests; the iOS suite adds 5 native-adapter tests.

## Real two-account integration procedure — required before release

Use two physical devices (A and B) with different Apple Accounts, the same configured container, and the same Development or Production environment. Use a third device signed into B for private read-receipt verification if available. Do not use production personal bookmarks as test fixtures. Record the build number, iOS versions, environment, observed results and timestamps; never put account credentials in the report.

1. A launches the signed app, confirms iCloud availability and creates a library named “Family QA”. Verify the custom family zone exists in A's private database.
2. A creates “Recipes” with the food icon.
3. A saves `https://example.com/recipe-a` with the explicit title “A’s first link”. Verify the title/collection and **Up to date with iCloud** status.
4. A opens **Invite & manage family**, invites B privately, and B opens the invitation from Messages/Mail. Verify both cold-launch and already-running acceptance. Confirm “Join library” and verify the zone is in B's shared database, not B's private database.
5. B sees “Recipes” and A's link after refresh; record the shared record IDs, not personal identities.
6. B shares `https://example.com/recipe-b` using Safari → Share → linkin, chooses the shared library and Recipes, and saves without opening the main app. Wait for the extension's confirmed iCloud status. Repeat from YouTube, Instagram and Reddit where those apps expose a URL; unsupported shares must explain the issue and preserve input.
7. A refreshes and sees B's link once. Repeat the extension save and confirm no duplicate appears.
8. A saves another link and explicitly mentions B. Confirm ordinary saves/collection edits/deletions do not produce visible alerts.
9. B eventually sees the unread mention. With notifications authorized and the app backgrounded, observe whether iOS permits delivery. A missing background alert is not a failed sync guarantee: open the app and verify the unread mention appears. Test denied permission, Low Power Mode and force-quit separately; document delivery as best effort.
10. B swipes the mention to mark it read. Verify it disappears from B's unread list and its alert is removed. Refresh B's other device and verify the private receipt syncs; A must not see B's private notes or receipts in the shared zone.
11. Both users refresh and verify the same live shared links, collections, shared descriptions, authors and deletion results. Save a **private note** on B; it must only be visible on B's devices.

Additional release checks:

- Airplane mode: cached browsing/search, creating/moving/deleting links, and extension saving. Restore connectivity, reopen and verify one copy per queued operation.
- Edit distinct fields on A/B offline, then reconnect in either order. Both fields must converge. Same-field conflicts must resolve consistently and preserve the losing unsent value in the recovery copy.
- Remove a collection while another device moves a link into it. The link must remain visible as unfiled, never disappear.
- A changes B to view-only. B can browse and write private notes/read receipts, but cannot change shared records. B can leave the share. A can remove participants, stop sharing and delete the library.
- Revoke/delete a zone while B is offline with pending work. B must not recreate it or lose the pending work; verify the recovery export.
- Change Apple Accounts with pending operations. The old queue must not upload to the new account; the app must lock the old library.
- Tap a mention alert on cold/warm launch and verify navigation to its link. Deleted-link alerts should be removed after refresh.
- Test iCloud storage full, restricted account, disabled iCloud Drive, network loss during upload, and long/blocked preview sites. Saving a URL must not depend on preview success.
- Run on iOS 17 and the latest release; check iPhone portrait/landscape, iPad split view/multitasking, largest accessibility text sizes, VoiceOver labels/actions, light/dark appearance and keyboard navigation.
- Validate a signed Release archive in Organizer, inspect its entitlements/privacy report, deploy the schema to Production, and repeat the core scenario with TestFlight before release.

## Test boundaries and limitations

`FamilyScenarioTests` is a realistic **test double** for owner/private and participant/shared projections. It checks two identities, shared additions/deletions, recipient filtering, and private notes/receipts across devices. It does not call CloudKit or prove invitation delivery, entitlements, provisioning or APNs. `AppleMappingTests` and `AttachmentReaderTests` use actual framework objects locally, with no account or external website.

The local database stores a Codable snapshot and outbox in a SQLite transaction. This keeps cross-process commits atomic but rewrites the snapshot per mutation; very large libraries need additional device-scale storage benchmarks before release. The search benchmark covers 2,000 links plus 2,000 notes and is not a benchmark of cloud upload or full-store mutation throughput. There is no automatic purge of CloudKit tombstones in v1, to avoid resurrecting edits from long-offline devices.
