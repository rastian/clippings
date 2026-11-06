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
