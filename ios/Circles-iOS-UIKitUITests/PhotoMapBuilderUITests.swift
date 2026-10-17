import XCTest

/// Add from photos, end to end on a seeded simulator (geotagged test photos,
/// a throwaway account): the hub, Scan a time period → review → a new
/// circle, then Build my map → review → Places from my photos.
final class PhotoMapBuilderUITests: XCTestCase {
    func testAddFromPhotos() throws {
        let app = XCUIApplication()
        app.launch()
        for label in ["Continue", "Not now", "Skip", "Done"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 4) { button.tap(); sleep(2) }
        }
        sleep(3)

        // Add Place → Add from photos → the hub
        openHub(app)
        snap(app, "01-hub")

        // Scan a time period → this month
        tapCard(app, "Scan a time period")
        allowPhotos()
        let month = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2026'")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 20), "months listed")
        snap(app, "02-period")
        month.tap()
        let find = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Find places in'")).firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()

        // Review: wait for Apple Maps to look at every spot
        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Done'")).firstMatch
        _ = done.waitForExistence(timeout: 90)
        snap(app, "03-review-period")
        let firstRow = app.cells.element(boundBy: 0)
        if firstRow.exists { firstRow.tap() }   // leave one out
        snap(app, "04-one-unchecked")
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save ' AND label CONTAINS 'place' AND NOT (label BEGINSWITH 'Save to')")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        sleep(12)
        snap(app, "05-new-circle")

        // Back home → Build my map
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(2)
        openHub(app)
        tapCard(app, "Build my map")
        let build = app.buttons["Build my map"]
        XCTAssertTrue(build.waitForExistence(timeout: 10))
        build.tap()
        allowPhotos()
        _ = done.waitForExistence(timeout: 90)
        snap(app, "06-review-map")
        if save.waitForExistence(timeout: 5) { save.tap() }
        sleep(12)
        snap(app, "07-saved-map")
    }

    private func openHub(_ app: XCUIApplication) {
        let addPlace = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Place'")).firstMatch
        XCTAssertTrue(addPlace.waitForExistence(timeout: 20), "Add Place on Home")
        addPlace.tap()
        let item = app.buttons["Add from photos"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu item")
        item.tap()
        sleep(2)
    }

    private func tapCard(_ app: XCUIApplication, _ title: String) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "card \(title)")
        card.tap()
    }

    private func allowPhotos() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
