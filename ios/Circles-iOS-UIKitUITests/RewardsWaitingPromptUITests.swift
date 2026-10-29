import XCTest

/// A store QR scanned before there's an account (2026-10-29, Wes's iPad froze
/// on "Rewards Waiting!"): on a signed-out install, opening the store link
/// cold shows the prompt over the login screen, both buttons respond, and
/// Sign Up lands on Create Account. Needs a signed-out app on the simulator
/// (uninstall + reinstall first).
@available(iOS 16.4, *)
final class RewardsWaitingPromptUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func openStoreLink(_ app: XCUIApplication) {
        app.open(URL(string: "circles://sticker?code=3OZM82")!)
        // System alerts over a fresh install (Apple Account, paste) hold the
        // app inactive; the prompt must still show once they're answered
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Allow Paste", "Don’t Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 4) { button.tap() }
        }
    }

    func testSignUpOpensCreateAccount() {
        let app = XCUIApplication()
        openStoreLink(app)
        let alert = app.alerts["Rewards Waiting! 🎁"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "the prompt shows on a cold open")
        alert.buttons["Sign Up"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Sign Up dismisses the prompt")
        XCTAssertTrue(app.staticTexts["Save your favorite places — free"].waitForExistence(timeout: 5),
                      "Sign Up lands on Create Account")
    }

    func testLaterDismissesOverLogin() {
        let app = XCUIApplication()
        app.terminate()
        openStoreLink(app)
        let alert = app.alerts["Rewards Waiting! 🎁"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        alert.buttons["Later"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Later dismisses the prompt")
        XCTAssertTrue(app.buttons["Create an Account"].isHittable, "the login screen is usable underneath")
    }
}
