import XCTest

/// Scripted walkthrough of the app for marketing screen-recordings.
/// Run with `simctl io booted recordVideo` capturing while this test drives
/// the real app. Long holds give each screen time on camera.
/// Mutation-free: never saves, likes, or posts anything.
final class Circles_iOS_UIKitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testMarketingTour() throws {
        let app = XCUIApplication()
        app.launch()
        hold(8) // Beat 1: home — populated map, connections strip, activity feed

        // Beat 2: Add Place -> Select Circle sheet (no save)
        let addPlace = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Place'")).firstMatch
        if tap(addPlace) {
            hold(6)
            goBack(app)
            hold(2)
        }

        // Beat 3: map filter -> All Connections (network pins)
        if tap(app.buttons["My Places"]) || tap(app.staticTexts["My Places"]) {
            hold(2)
            if !tap(app.buttons["All Connections"]) && !tap(app.staticTexts["All Connections"]) {
                closeDropdown(app)
            }
            hold(9)
        }

        // Beat 4: search Canopy -> real place page
        searchAndOpen(app, query: "Canopy", resultLabel: "Canopy Cocktails & Garden")
        hold(8)
        app.swipeUp()
        hold(4)
        goBack(app)
        hold(2)

        // Beat 5: Brittany's profile via the connections strip -> View Profile
        closeDropdown(app)
        if tap(app.staticTexts["Brittany C"]) || tap(app.otherElements["Brittany C"]) {
            hold(2)
            if !tap(app.buttons["View Profile"]) {
                _ = tap(app.sheets.buttons["View Profile"].firstMatch)
            }
            hold(7)
            app.swipeUp()
            hold(4)
            goBack(app)
        }
        closeDropdown(app)
        hold(2)

        // Beat 6: Me tab — my own circles, organized
        if tap(app.tabBars.buttons["Me"]) {
            hold(7)
            app.swipeUp()
            hold(3)
            tap(app.tabBars.buttons["Home"])
            hold(2)
        }

        // Beat 7: Rewards ($ nav icon) -> Piggy Bank (default tab)
        if !tap(app.buttons["Rewards"]) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.771, dy: 0.088)).tap()
        }
        hold(9)
        goBack(app)
        hold(2)

        // Beat 8: Specials segment
        if !tap(app.buttons["Specials"]) { tap(app.staticTexts["Specials"]) }
        hold(8)
    }

    func testCaptureExtras() throws {
        let app = XCUIApplication()
        app.launch()
        hold(6)

        // A circle full of places: Me tab -> tap a circle card
        if tap(app.tabBars.buttons["Me"]) {
            hold(3)
            if tap(app.staticTexts["Asbury Park"]) || tap(app.staticTexts["Belmont"]) || tap(app.staticTexts["Charlotte NC"]) {
                hold(6)
                goBack(app)
                hold(2)
            }
        }

        // Brittany's profile: My Network -> My People -> Brittany C
        if tap(app.tabBars.buttons["My Network"]) {
            hold(3)
            tap(app.buttons["My People"])
            hold(3)
            if tap(app.staticTexts["Brittany C"]) || tap(app.cells.staticTexts["Brittany C"].firstMatch) {
                hold(7)
            }
        }
        hold(2)
    }

    /// Type into the home search bar and open the first matching result.
    private func searchAndOpen(_ app: XCUIApplication, query: String, resultLabel: String) {
        var search = app.textFields["Search places and people"]
        if !search.exists { search = app.searchFields.firstMatch }
        guard search.waitForExistence(timeout: 5) else { return }
        search.tap()
        hold(1)
        // clear any previous query
        let clear = app.buttons["Clear text"]
        if clear.exists && clear.isHittable { clear.tap() }
        search.typeText(query)
        hold(3)
        let result = app.staticTexts[resultLabel].firstMatch
        if !tap(result) {
            tap(app.cells.firstMatch)
        }
    }

    /// Close the map people-filter dropdown if it's open (it blocks other taps).
    private func closeDropdown(_ app: XCUIApplication) {
        if app.staticTexts["All Connections"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
            hold(1)
        }
    }

    @discardableResult
    private func tap(_ el: XCUIElement) -> Bool {
        guard el.waitForExistence(timeout: 4), el.isHittable else { return false }
        el.tap()
        return true
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable {
            back.tap()
            return
        }
        // edge-swipe back for custom navigation
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func hold(_ s: UInt32) { sleep(s) }
}
