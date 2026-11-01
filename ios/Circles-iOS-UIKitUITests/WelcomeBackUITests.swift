import XCTest

/// The login screen's "Welcome back" (2026-11-01): after a logout the phone
/// remembers who signed in and how. Needs a signed-out app on the simulator
/// (`xcrun simctl keychain <device> reset` first).
final class WelcomeBackUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(method: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-lastAccountOnDevice",
                                "{id = \"test-u1\"; email = \"sam.rivera@gmail.com\"; displayName = \"Sam Rivera\"; method = \"\(method)\"; at = 1761990000; }"]
        app.launch()
        // Fresh-keychain system prompts (Apple Account) sit over the app
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Don’t Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 4) { button.tap() }
        }
        return app
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testGoogleAccountShowsContinueWithGoogle() {
        let app = launch(method: "google")
        XCTAssertTrue(app.staticTexts["Welcome back, Sam"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Last time you used Google · sam.rivera@gmail.com"].exists)
        XCTAssertEqual(app.buttons["welcomeBackContinue"].label, "Continue with Google")
        XCTAssertFalse(app.buttons["Create an Account"].isHittable, "a returning person skips the new-account pitch")
        snapshot("welcome-back-google")

        app.buttons["welcomeBackNotYou"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back, Sam"].waitForNonExistence(timeout: 5), "Not you? removes the card")
        XCTAssertTrue(app.buttons["Create an Account"].waitForExistence(timeout: 5))
        snapshot("after-not-you")
    }

    func testPasswordAccountSaysEmailAndPassword() {
        let app = launch(method: "email")
        XCTAssertTrue(app.staticTexts["Last time you used your email and password · sam.rivera@gmail.com"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["welcomeBackContinue"].label, "Continue")
        snapshot("welcome-back-password")
    }
}
