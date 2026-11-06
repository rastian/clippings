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
