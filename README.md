# linkin

Your family’s corner of the internet.

A private native iOS bookmark library built with SwiftUI, CloudKit and Apple's sharing infrastructure. No app account, advertising, subscription or analytics.

Requires Xcode 26 with Swift 6 and an iOS simulator; deployment target is iOS 17. Open `linkin.xcodeproj`, select **linkin**, and run on a simulator. Core tests: `swift test`. App tests: `xcodebuild test -project linkin.xcodeproj -scheme linkin -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`.

Apple Developer signing and CloudKit configuration are required for real iCloud sharing. This repository does not contain credentials. See `ARCHITECTURE.md` for design decisions. Further setup and test documentation is added alongside each implementation milestone.
