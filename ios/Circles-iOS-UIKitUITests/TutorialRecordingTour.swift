import XCTest

/// Drives the app through the tutorial video's walkthrough while
/// `simctl io recordVideo` films it (Marketing/tutorial-2026-11/record.sh).
/// Each step prints "TOURMARK <epoch> <name>" so the build script can place
/// narration and captions. Skipped unless TOUR_RECORD=1.
final class TutorialRecordingTour: XCTestCase {
    private let app = XCUIApplication()
    private let env = ProcessInfo.processInfo.environment
    /// Whose map the person step shows, which circle closes the tour, and
    /// whether Add Place really saves (off on a real account: a save posts
    /// to followers and credits FavCoins)
    private var person: String { env["TOUR_PERSON"].flatMap { $0.isEmpty ? nil : $0 } ?? "Brittany R" }
    private var circleName: String { env["TOUR_CIRCLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "Favorite Local Spots" }
    private var saves: Bool { env["TOUR_SAVE"] != "0" }

    override func setUp() { continueAfterFailure = true }

    private func mark(_ name: String) {
        print(String(format: "TOURMARK %.3f %@", Date().timeIntervalSince1970, name))
    }

    private func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    @discardableResult
    private func tap(_ element: XCUIElement, wait: Double = 6) -> Bool {
        guard element.waitForExistence(timeout: wait), element.isHittable else { return false }
        element.tap()
        return true
    }

    /// A gentle scroll of the lower half (the activity list), never the map
    private func scrollList(up: Bool = true) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.88 : 0.62))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.62 : 0.88))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// Taps where the element is, even when XCUITest calls it not hittable
    private func tapAt(_ element: XCUIElement, wait: Double = 6) -> Bool {
        guard element.waitForExistence(timeout: wait) else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// The map's person chip back to Everyone
    private func mapEveryone() {
        for name in ["Wesley", "Brittany R"] where app.buttons[name].exists {
            app.buttons[name].tap(); hold(1)
            if app.buttons["Everyone"].exists { app.buttons["Everyone"].tap() }
            else if app.staticTexts["Everyone"].exists { app.staticTexts["Everyone"].tap() }
            hold(1.5)
        }
    }

    /// Home scrolled to the top by its tab (a drag there would pan the map)
    private func homeToTop() {
        tap(app.tabBars.buttons["Home"]); hold(0.6)
        tap(app.tabBars.buttons["Home"]); hold(0.8)
    }

    /// Back to the previous screen: the nav bar's back button, else a swipe
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists, back.isHittable { back.tap() } else {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
        hold(1.2)
    }

    private func closeSheet() {
        if app.alerts.count > 0 {
            let alert = app.alerts.firstMatch
            for label in ["Discard", "OK", "Not Now", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); hold(0.8); break
            }
        }
        for label in ["Keep Exploring", "Cancel", "Close", "Done", "Not now", "Not Now", "Skip"] where app.buttons[label].exists && app.buttons[label].isHittable {
            app.buttons[label].tap(); hold(1.0); return
        }
    }

    func testRecordTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOUR_RECORD"] == "1")
        // Every take starts fresh on Home
        app.launch()

        // Off camera: clear first-launch sheets and hints
        if app.buttons["Not now"].waitForExistence(timeout: 6) { app.buttons["Not now"].tap(); hold(1.5) }
        if app.buttons["Continue"].waitForExistence(timeout: 4) { app.buttons["Continue"].tap(); hold(1.5) }
        if app.buttons["Got it"].waitForExistence(timeout: 4) { app.buttons["Got it"].tap() }
        XCTAssertTrue(app.staticTexts["Recent Activity"].waitForExistence(timeout: 20))
        // A person picked on the map last take: back to Everyone
        mapEveryone()
        // Warm Locals and Widgets so they're loaded and hint-free on camera
        tap(app.buttons["Locals"]); hold(6)
        tap(app.buttons["Widgets"]); hold(3)
        if app.buttons["Got it"].exists { app.buttons["Got it"].tap(); hold(1) }
        tap(app.buttons["Moments"]); hold(3)
        tap(app.buttons["Activity"]); hold(3)
        // ...and check-in's nearby list
        tapAt(app.buttons["Check in"]); hold(7)
        closeSheet()
        // Home from the top: the map in view
        homeToTop()
        hold(2.5)
        mark("start")

        // 1. Home
        mark("home"); hold(5)

        // 2. One person's places on the map
        mark("person")
        tap(app.staticTexts[person])
        hold(1.8)
        if app.staticTexts["Show their places"].exists { app.staticTexts["Show their places"].tap() }
        else if app.buttons["Show their places"].exists { app.buttons["Show their places"].tap() }
        hold(4)
        mapEveryone()

        // 3. Recent activity
        mark("activity")
        scrollList(); hold(2.5)

        // 4. A place page
        mark("place")
        if let query = env["TOUR_SEARCH"], !query.isEmpty {
            // Search anything: a place by name, then its page
            let field = app.searchFields["Search anything"]
            // Wait for the keyboard before typing (a tap can land before focus)
            for _ in 0..<3 where app.keyboards.count == 0 {
                tapAt(field); _ = app.keyboards.firstMatch.waitForExistence(timeout: 2.5)
            }
            app.typeText(query); hold(3)
            let hit = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", query)).element(boundBy: 1)
            if hit.exists { hit.tap() } else { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", query)).firstMatch.tap() }
            hold(1.0)
            mark("place-page")
            hold(3.5)
            scrollList(); hold(3)
            goBack()
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap(); hold(0.8) }
            homeToTop(); hold(1)
        } else {
        let row = app.cells.containing(.staticText, identifier: "Brittany R added Pasta & Provisions to Charlotte 🫶").firstMatch
        if !tap(row, wait: 3) {
            // The first single place someone added (not a "Show all" group)
            let single = app.cells.containing(NSPredicate(format: "label CONTAINS ' added ' AND NOT (label CONTAINS 'Show all')")).firstMatch
            tap(single, wait: 3)
        }
        hold(4)
        scrollList(); hold(3)
        goBack()
        homeToTop(); hold(1)
        }

        // 5. Add a place
        mark("add")
        tapAt(app.buttons[" Add Place"])
        hold(1.2)
        tapAt(app.buttons["Search for a place"], wait: 3)
        hold(1.5)
        // It asks which circle first
        let pick = circleName
        if !app.staticTexts[pick].waitForExistence(timeout: 3) {
            let find = app.searchFields["Search circles..."]
            if find.exists {
                find.tap(); _ = app.keyboards.firstMatch.waitForExistence(timeout: 2.5)
                if app.keyboards.count > 0 { app.typeText(String(pick.prefix(9))) }
                hold(1.2)
            }
        }
        if app.staticTexts[pick].exists { app.staticTexts[pick].tap(); hold(1.5) }
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue != 'Search anything' AND placeholderValue != 'Search circles...'")).firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Amelie's French Bakery")
            hold(3.5)
            // The second row is the bakery itself (the first searches nearby)
            _ = app.cells.element(boundBy: 1).waitForExistence(timeout: 6)
            let result = app.cells.count > 1 ? app.cells.element(boundBy: 1) : app.cells.firstMatch
            if tap(result, wait: 2) { hold(3.5) }
            mark("add-form")
            hold(2.5)
            if !saves {
                // Shown, not saved: back out and discard
                hold(2.5)
                let close = app.buttons["Close"].exists ? app.buttons["Close"] : app.navigationBars.buttons.firstMatch
                tapAt(close, wait: 2); hold(1.2)
                closeSheet()
            } else {
            tapAt(app.buttons["Save Place"], wait: 3)
            hold(2.5)
            // "How was it?" — a 9
            mark("rate")
            if app.buttons["9"].waitForExistence(timeout: 4) { app.buttons["9"].tap() }
            else if app.staticTexts["9"].exists { app.staticTexts["9"].tap() }
            hold(3.5)
            // The first-place badge, then back Home
            if app.buttons["Keep Exploring"].waitForExistence(timeout: 6) { hold(2.5); app.buttons["Keep Exploring"].tap(); hold(1.2) }
            }
        }
        closeSheet(); closeSheet()
        if !app.staticTexts["Recent Activity"].exists { goBack() }

        // 6. Moments, Locals, Widgets
        // Marks land as each screen appears, so narration matches it
        homeToTop()
        tap(app.buttons["Moments"]); mark("moments"); hold(5)
        tap(app.buttons["Locals"]); mark("locals"); hold(5)
        tap(app.buttons["Widgets"]); mark("widgets"); hold(4.5)
        tap(app.buttons["Activity"]); hold(1)

        // 7. Check in
        homeToTop()
        tapAt(app.buttons["Check in"]); mark("checkin"); hold(2.5)
        tap(app.buttons["Nearby"], wait: 2); hold(4)
        closeSheet()
        if !app.staticTexts["Recent Activity"].exists { goBack() }

        // 8. Rewards
        homeToTop()
        tapAt(app.buttons["Rewards"]); mark("rewards"); hold(5)
        closeSheet()
        if !app.staticTexts["Recent Activity"].exists { goBack() }

        // 9. Profile
        tap(app.tabBars.buttons["Me"]); mark("profile"); hold(4)
        if !app.staticTexts[circleName].exists { scrollList() ; hold(1) }
        tapAt(app.staticTexts[circleName], wait: 4); mark("circle"); hold(5)

        mark("end")
        hold(1.5)
    }
}
