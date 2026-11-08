import XCTest

@MainActor
final class ClippingsUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons["addLink"].waitForExistence(timeout: 10))
    }
    func openCollections() {
        if app.buttons["showCollections"].exists { app.buttons["showCollections"].tap() }
    }
    func closeCollections() {
        if app.navigationBars["Collections"].buttons["Done"].exists { app.navigationBars["Collections"].buttons["Done"].tap() }
    }
    func testOnboardingCollectionsAndSaving() {
        createLibrary()
        openCollections()
        app.buttons["newCollection"].tap()
        app.textFields["collectionName"].tap(); app.textFields["collectionName"].typeText("Recipes")
        app.buttons["saveCollection"].tap()
        XCTAssertTrue(app.staticTexts["Recipes"].waitForExistence(timeout: 5))
        closeCollections()
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

extension ClippingsUITests {
    func testSwipeDeleteConfirmationStaysWithScrolledCard() {
        app.terminate()
        app.launchArguments = standardArguments + ["--reset", "--shared-library", "--swipe-cards"]
        app.launch()
        let card = app.buttons["clipping-clipping-2"]
        XCTAssertTrue(app.buttons["clipping-pasta"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(card.isHittable)
        // A short swipe reveals the action without triggering a full swipe.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        keepScreenshot("Red swipe action")
        app.buttons["Delete"].tap()
        let confirm = app.buttons["Delete link"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        keepScreenshot("Confirmation on scrolled card")
        // On popover presentations the confirmation must sit beside the selected row,
        // not above the list's section header. Sheets on older iOS are also valid.
        XCTAssertGreaterThan(confirm.frame.midY, card.frame.maxY)
        dismissDeleteConfirmation()
        XCTAssertTrue(card.isHittable)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(card.exists, "A full swipe must not remove the card before confirmation")
        confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["clipping-clipping-3"].exists)
    }
    func testReadOnlyCardsHaveNoSwipeDelete() {
        app.terminate()
        app.launchArguments = standardArguments + ["--reset", "--shared-library", "--read-only"]
        app.launch()
        let card = app.buttons["clipping-pasta"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Delete link"].exists)
        // With no swipe action, SwiftUI may treat the gesture as opening the card.
        if app.buttons["mentionSomeone"].waitForExistence(timeout: 2) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
    private func dismissDeleteConfirmation() {
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Delete link"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
    private func keepScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testNewspaperCards() {
            app.terminate()
            app.launchArguments = standardArguments + ["--reset", "--shared-library"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Freshly clipped"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Clippings"].exists)
            XCTAssertTrue(app.staticTexts["clippingExcerpt"].exists)
            XCTAssertTrue(app.staticTexts["Weekend pasta"].isHittable)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Sunday paper"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.staticTexts["Weekend pasta"].tap()
            XCTAssertTrue(app.buttons["mentionSomeone"].waitForExistence(timeout: 5))
    }
    func testSaveLinkCanMentionOwnerMissingFromCachedMembers() {
        app.terminate()
        app.launchArguments = standardArguments + ["--reset", "--shared-library", "--missing-owner"]
        app.launch()
        XCTAssertTrue(app.buttons["addLink"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Family"].tap()
        XCTAssertTrue(app.staticTexts["Library owner"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        app.buttons["addLink"].tap()
        let owner = app.switches["mentionRecipient-owner"]
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        owner.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.textFields["linkURL"].tap(); app.textFields["linkURL"].typeText("https://example.com/trip")
        app.textFields["linkTitle"].tap(); app.textFields["linkTitle"].typeText("A family trip")
        app.buttons["saveLink"].tap()
        app.staticTexts["All links"].firstMatch.tap()
        app.staticTexts["A family trip"].firstMatch.tap()
        app.buttons["mentionSomeone"].tap()
        XCTAssertTrue(app.staticTexts["Already mentioned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["mentionRecipient-owner"].isEnabled)
    }
    func openSharedLink(readOnly: Bool = false) {
        app.terminate()
        app.launchArguments = standardArguments + ["--reset", "--shared-library"] + (readOnly ? ["--read-only"] : [])
        app.launch()
        XCTAssertTrue(app.staticTexts["All links"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["All links"].firstMatch.tap()
        app.staticTexts["Weekend pasta"].firstMatch.tap()
    }
    func testInvitedMemberCanMentionOwnerOnSavedLink() {
        openSharedLink()
        app.buttons["mentionSomeone"].tap()
        let owner = app.switches["mentionRecipient-owner"]
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["mentionRecipient-participant"].exists)
        XCTAssertFalse(app.buttons["sendMentions"].isEnabled)
        // SwiftUI exposes the whole row as a switch; tap the trailing control.
        owner.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["sendMentions"].isEnabled)
        app.buttons["sendMentions"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["sendMentions"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["mentionSomeone"].tap()
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertFalse(owner.isEnabled)
        XCTAssertTrue(app.staticTexts["Already mentioned"].exists)
        XCTAssertFalse(app.buttons["sendMentions"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Invited member mentioned the owner"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testViewOnlyMemberSeesWhyMentionsAreUnavailable() {
        openSharedLink(readOnly: true)
        XCTAssertTrue(app.buttons["mentionSomeone"].exists)
        XCTAssertFalse(app.buttons["mentionSomeone"].isEnabled)
        XCTAssertTrue(app.staticTexts["You need editing access to mention someone in this library."].exists)
    }
    func addLink(title: String = "Weekend pasta", url: String = "https://example.com/pasta", detail: Bool = false) {
        app.buttons[app.buttons["addLink"].exists ? "addLink" : "addLinkDetail"].tap()
        app.textFields["linkURL"].tap(); app.textFields["linkURL"].typeText(url)
        app.textFields["linkTitle"].tap(); app.textFields["linkTitle"].typeText(title)
        app.buttons["saveLink"].tap()
    }
    func createCollection(_ name: String) {
        openCollections()
        app.buttons["newCollection"].tap()
        app.textFields["collectionName"].tap(); app.textFields["collectionName"].typeText(name)
        app.buttons["saveCollection"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        closeCollections()
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
        openCollections()
        app.staticTexts["Recipes"].firstMatch.tap()
        addLink(detail: true)
        XCTAssertTrue(app.staticTexts["Weekend pasta"].waitForExistence(timeout: 5))
        if app.buttons["showCollections"].exists { openCollections() }
        else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let recipe = app.buttons["collectionChoice-Recipes"].exists ? app.buttons["collectionChoice-Recipes"] : app.staticTexts["Recipes"].firstMatch
        recipe.press(forDuration: 1)
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
