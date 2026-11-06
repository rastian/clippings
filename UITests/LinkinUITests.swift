import XCTest

@MainActor
final class LinkinUITests: XCTestCase {
    let app = XCUIApplication()
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app.launchArguments = ["--ui-testing", "--reset"]; app.launch()
        }
    }
    func createLibrary() {
        XCTAssertTrue(app.buttons["createLibrary"].waitForExistence(timeout: 10))
        app.buttons["createLibrary"].tap()
        XCTAssertTrue(app.buttons["newCollection"].waitForExistence(timeout: 10))
    }
    func testOnboardingCollectionsAndSaving() {
        createLibrary()
        app.buttons["newCollection"].tap()
        app.textFields["collectionName"].tap(); app.textFields["collectionName"].typeText("Recipes")
        app.buttons["saveCollection"].tap()
        XCTAssertTrue(app.staticTexts["Recipes"].waitForExistence(timeout: 5))
        app.buttons["addLink"].tap()
        app.textFields["linkURL"].tap(); app.textFields["linkURL"].typeText("https://example.com/pasta")
        app.textFields["linkTitle"].tap(); app.textFields["linkTitle"].typeText("Weekend pasta")
        app.buttons["saveLink"].tap()
        app.staticTexts["All links"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Weekend pasta"].waitForExistence(timeout: 5))
    }
    func testInvalidURLShowsError() {
        createLibrary(); app.buttons["addLink"].tap()
        app.textFields["linkURL"].tap(); app.textFields["linkURL"].typeText("not-a-url")
        app.buttons["saveLink"].tap()
        XCTAssertTrue(app.alerts["Something needs attention"].waitForExistence(timeout: 5))
    }
    func testTabsAndEmptyMentions() {
        createLibrary()
        app.tabBars.buttons["Mentions"].tap()
        XCTAssertTrue(app.staticTexts["You’re all caught up"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Family"].tap()
        XCTAssertTrue(app.staticTexts["No advertising or tracking"].waitForExistence(timeout: 5))
    }
}
