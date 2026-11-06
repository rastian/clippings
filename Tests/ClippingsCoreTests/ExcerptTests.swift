import XCTest
#if canImport(ClippingsCore)
@testable import ClippingsCore
#else
@testable import Clippings
#endif

final class ExcerptTests: XCTestCase {
    func testArticleOpeningWinsOverMarketingDescriptionAndNavigation() {
        let html = """
        <meta name="description" content="Subscribe to our latest news.">
        <article><nav><p>A long navigation menu that should never appear in the article preview.</p></nav>
        <p>Take the little path past the harbour and follow it down to the water. There is a quiet beach at the end.</p>
        <p>This third sentence should not appear in the card.</p></article>
        """
        XCTAssertEqual(ArticleExcerpt.extract(from: html), "Take the little path past the harbour and follow it down to the water. There is a quiet beach at the end.")
    }
    func testMetadataFallbackHandlesAttributeOrderAndEntities() {
        XCTAssertEqual(ArticleExcerpt.extract(from: "<meta content='A calm &amp; quiet morning. Bring &#x2018;your&#x2019; notebook.' property='og:description'>"), "A calm & quiet morning. Bring ‘your’ notebook.")
        XCTAssertEqual(ArticleExcerpt.extract(from: "<META CONTENT=Welcome NAME=description>"), "Welcome")
    }
    func testMainContentStripsScriptsAndFormatting() {
        let html = "<main><script><p>This fake paragraph should not become a preview at any time.</p></script><p>This is a <strong>long enough</strong> opening paragraph for an article. It has another sentence.</p></main>"
        XCTAssertEqual(ArticleExcerpt.extract(from: html), "This is a long enough opening paragraph for an article. It has another sentence.")
    }
    func testMissingMetadataAndBoundedPreview() {
        XCTAssertNil(ArticleExcerpt.extract(from: "<body><nav>Menu</nav><script>secret()</script></body>"))
        XCTAssertNil(ArticleExcerpt.preview("  \n"))
        let long = ArticleExcerpt.preview(String(repeating: "Long article text ", count: 100))!
        XCTAssertLessThanOrEqual(long.count, 360)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
