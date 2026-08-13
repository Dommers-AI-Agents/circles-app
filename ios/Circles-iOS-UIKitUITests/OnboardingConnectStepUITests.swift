import XCTest

/// Verifies the post-add-place tutorial step: the "Find Your People" bubble on
/// the My Network tab and the connect action sheet behind its Next button.
/// Expects the app's UserDefaults to be seeded with welcome/createCircle/
/// addPlace completed and shouldShowTutorial=true (see session notes — the
/// harness seeds the container plist before running).
final class OnboardingConnectStepUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConnectStepFlow() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(6) // let home settle + tutorial-status check complete

        app.tabBars.buttons["My Network"].tap()

        // The Find Your People bubble should appear pointing at the invite button
        XCTAssertTrue(app.staticTexts["Find Your People"].waitForExistence(timeout: 10),
                      "exploreNetwork bubble did not appear on My Network tab")
        sleep(6) // hold for external screenshot

        app.buttons["Next"].tap()

        // Next should open the connect action sheet, not yank to the Me tab
        XCTAssertTrue(app.buttons["Invite My Best Friend"].waitForExistence(timeout: 5),
                      "connect action sheet did not appear after Next")
        XCTAssertTrue(app.buttons["Search People I Know"].exists)
        sleep(6) // hold for external screenshot

        // Take the search path — keyboard should come up on the network list
        app.buttons["Search People I Know"].tap()
        sleep(2)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "search bar did not take focus")
        sleep(6) // hold for external screenshot
    }
}
