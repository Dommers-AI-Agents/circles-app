import XCTest

/// Clubs, end to end on a simulator signed in as a throwaway organizer whose
/// club already has meetups, an RSVP, a bulletin and a board post (set up
/// through the API): Widgets → Clubs → the club, scrolled top to bottom.
final class ClubsUITests: XCTestCase {
    func testClubPage() throws {
        let app = XCUIApplication()
        app.launch()
        // Never "Continue" on first-run sheets: it follows real accounts
        for label in ["Not now", "Skip", "Done", "Later"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 3) { button.tap(); sleep(1) }
        }
        sleep(3)
        // The people sheet: swipe it away (its Continue follows people)
        for _ in 0..<3 where app.staticTexts["Explore other people's maps \u{1F5FA}\u{FE0F}"].exists || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Explore other people'")).firstMatch.exists {
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            sleep(2)
        }
        for label in ["Not now", "Skip", "Done", "Later"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap(); sleep(1) }
        }
        snap(app, "00-launch")

        let widgets = app.buttons["Widgets"].firstMatch
        XCTAssertTrue(widgets.waitForExistence(timeout: 15), "Widgets segment")
        widgets.tap()
        sleep(2)
        let clubs = app.staticTexts["Clubs"].firstMatch
        for _ in 0..<8 where !clubs.isHittable { app.swipeUp(); sleep(1) }
        snap(app, "01-widgets")
        XCTAssertTrue(clubs.waitForExistence(timeout: 5), "Clubs card")
        clubs.tap()
        sleep(4)
        snap(app, "02-my-clubs")

        let club = app.staticTexts["Test Run Club"].firstMatch
        XCTAssertTrue(club.waitForExistence(timeout: 10), "the club is listed")
        club.tap()
        sleep(5)
        snap(app, "03-club-top")
        for i in 4...8 {
            app.swipeUp()
            sleep(2)
            snap(app, String(format: "%02d-club-scroll", i))
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
