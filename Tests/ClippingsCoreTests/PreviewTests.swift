#if canImport(UIKit) && !canImport(ClippingsCore)
import XCTest
import UIKit
import LinkPresentation
@testable import Clippings

@MainActor
final class PreviewTests: XCTestCase {
    private final class Provider: MetadataProviding {
        var calls = 0
        var fails = false
        func metadata(for url: URL) async throws -> LPLinkMetadata {
            calls += 1
            if fails { throw URLError(.timedOut) }
            let metadata = LPLinkMetadata()
            metadata.title = "A day by the sea"
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            }
            metadata.imageProvider = NSItemProvider(object: image)
            return metadata
        }
    }
    func testThumbnailAndExcerptLoadTogetherAndAreReused() async throws {
        let provider = Provider()
        let service = ClippingPreviewService(metadataProvider: provider, loadExcerpt: { _ in "A quiet beach. A day worth keeping." })
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let first = await service.preview(for: url)
        XCTAssertEqual(first.title, "A day by the sea")
        XCTAssertNotNil(first.image)
        XCTAssertLessThanOrEqual(try XCTUnwrap(first.image).size.width, 800)
        XCTAssertEqual(first.excerpt, "A quiet beach. A day worth keeping.")
        _ = await service.preview(for: url)
        XCTAssertEqual(provider.calls, 1)
    }
    func testImageFailureKeepsTheAvailableExcerpt() async throws {
        let provider = Provider(); provider.fails = true
        let service = ClippingPreviewService(metadataProvider: provider, loadExcerpt: { _ in "The website description is still available." })
        let result = await service.preview(for: try XCTUnwrap(URL(string: "https://example.com/article")))
        XCTAssertNil(result.image)
        XCTAssertEqual(result.excerpt, "The website description is still available.")
    }
}
#endif
