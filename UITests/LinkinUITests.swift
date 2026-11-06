import XCTest

@MainActor
final class LinkinUITests: XCTestCase {
    let app = XCUIApplication()
    let standardArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app.launchArguments = standardArguments + ["--reset"]; app.launch()
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
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No advertising or tracking"].waitForExistence(timeout: 5))
    }
}

extension LinkinUITests {
    func addLink(title: String = "Weekend pasta", url: String = "https://example.com/pasta", detail: Bool = false) {
        app.buttons[detail ? "addLinkDetail" : "addLink"].tap()
        app.textFields["linkURL"].tap(); app.textFields["linkURL"].typeText(url)
        app.textFields["linkTitle"].tap(); app.textFields["linkTitle"].typeText(title)
        app.buttons["saveLink"].tap()
    }
    func createCollection(_ name: String) {
        app.buttons["newCollection"].tap()
        app.textFields["collectionName"].tap(); app.textFields["collectionName"].typeText(name)
        app.buttons["saveCollection"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }
    func testSearchNotesMoveAndDelete() {
        createLibrary(); createCollection("Recipes"); addLink()
        app.staticTexts["All links"].firstMatch.tap()
        app.staticTexts["Weekend pasta"].firstMatch.tap()
        app.buttons["moveCollection"].tap()
        app.buttons["Recipes"].tap()
        app.swipeUp()
        let note = app.textFields["personalNote"].exists ? app.textFields["personalNote"] : app.textViews["personalNote"]
        note.tap(); note.typeText("Grandma’s favourite")
        app.buttons["saveChanges"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Grandma")
        XCTAssertTrue(app.staticTexts["Weekend pasta"].waitForExistence(timeout: 5))
        app.staticTexts["Weekend pasta"].firstMatch.tap()
        app.swipeUp()
        app.buttons["deleteLink"].tap()
        app.sheets.buttons["Delete link"].tap()
        XCTAssertTrue(app.navigationBars["All links"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weekend pasta"].exists)
    }
    func testDeletingCollectionKeepsItsLinks() {
        createLibrary(); createCollection("Recipes")
        app.staticTexts["Recipes"].firstMatch.tap()
        addLink(detail: true)
        XCTAssertTrue(app.staticTexts["Weekend pasta"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Recipes"].firstMatch.press(forDuration: 1)
        app.buttons["Delete collection"].tap()
        app.sheets.buttons["Delete collection"].tap()
        app.staticTexts["Unfiled"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Weekend pasta"].waitForExistence(timeout: 5))
    }
    func testSavedLinksPersistAcrossLaunches() {
        createLibrary(); addLink()
        app.terminate(); app.launchArguments = standardArguments; app.launch()
        XCTAssertTrue(app.staticTexts["All links"].waitForExistence(timeout: 10))
        app.staticTexts["All links"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Weekend pasta"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Saved links"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testLargestDynamicTypeAndEmptyState() {
        app.terminate()
        app.launchArguments = standardArguments + ["--reset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["createLibrary"].waitForExistence(timeout: 10))
        app.swipeUp(); app.buttons["createLibrary"].tap()
        XCTAssertTrue(app.staticTexts["All links"].waitForExistence(timeout: 10))
        app.staticTexts["All links"].firstMatch.tap()
        XCTAssertTrue(app.buttons["addFirstLink"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["addFirstLink"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Largest Dynamic Type"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["addFirstLink"].tap()
        XCTAssertTrue(app.textFields["linkURL"].waitForExistence(timeout: 5))
    }
}
