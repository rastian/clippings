# Native simulator captures

Captured from the implemented app on 6 November 2026 with controlled test data; these are not design mockups or proof of configured iCloud sharing.

- `ipad-dark.png`: iPad Pro 11-inch, iOS 26.5, dark appearance and native split navigation.
- `iphone-largest-text.png`: iPhone 17 Pro, iOS 26.5, largest accessibility text size. The automated test also taps **Add a link** and verifies the editor opens.

Metadata fetching is disabled in the deterministic UI-test launch mode, so the sample link uses its domain fallback.

## Sunday paper design

- `sunday-paper-light.png`: iPhone 17 Pro, iOS 26.5, light appearance and the latest-clipping card.
- `sunday-paper-dark.png`: the same build with the simulator's system appearance set to dark.
- `sunday-paper-large-text.png`: the accessible empty state after removing an overlapping masthead.

These use isolated sample data and text-only fallbacks; network previews are disabled in UI-test mode. Thumbnail decoding/caching is checked separately with a controlled native image provider.
