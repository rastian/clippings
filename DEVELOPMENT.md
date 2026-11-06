# Development

Open `linkin.xcodeproj` in Xcode 26 or newer with Swift 6. The project is committed; no third-party package installation is needed. The minimum deployment target is iOS 17. CI builds without signing.

Run `swift test` for fast, deterministic domain and persistence tests on macOS. Run the shared `linkin` scheme's tests on an iOS simulator for the same tests against the actual app module plus XCUITest. See TESTING.md.

The project uses Xcode filesystem-synchronized groups. Adding files under App, Sources/LinkinCore, Tests/LinkinCoreTests or UITests automatically includes them. Run `python3 scripts/generate_project.py` after changing target configuration or shared extension source membership. Its output is deterministic.

Use Config/Local.xcconfig (ignored by Git) for DEVELOPMENT_TEAM and custom container, group and bundle IDs. Never commit signing material or credentials. App Store distribution requires additional Apple configuration; the default identifiers are project identifiers, not evidence of registered capabilities.

The unsigned simulator build uses a local app-support store when the App Group is unavailable. The production app uses the shared App Group. UI tests use a separate temporary store and disable external network metadata and iCloud; the reset flags only exist in Debug.

Recreate the original icon with `swift scripts/generate_icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

If the repository is inside iCloud Drive/Desktop and Xcode hangs before build planning, choose **Keep Downloaded** for the project in Finder. Keep DerivedData outside the synced folder. `python3 scripts/stage_for_validation.py` creates an ordinary temporary copy of build inputs under `/tmp/linkin-validation`; use its project with `-derivedDataPath /tmp/linkin-build`. Source edits and commits remain in the original repository.
