import XCTest

/// Walks a brand-new account through its first run the way a person would —
/// name, first favorite, the people sheet, location, more places, notifications,
/// then every home-tour bubble — slowly enough to film with `simctl io
/// recordVideo` (2026-11-12, so Wes can watch a new user's night from the
/// desk). Needs a fresh account's sign-in hand-off in the app group container
/// before launch (the App Clip's mailbox). Skipped unless NEW_USER_WALKTHROUGH=1.
final class NewUserWalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() { continueAfterFailure = true }

    private func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func mark(_ name: String) {
        print(String(format: "WALKMARK %.3f %@", Date().timeIntervalSince1970, name))
    }

    /// Taps the first of these buttons that is on screen; says which
    @discardableResult
    private func tapFirst(_ labels: [String], wait: Double = 8) -> String? {
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for label in labels {
                let button = app.buttons[label]
                if button.exists && button.isHittable { button.tap(); return label }
                let text = app.staticTexts[label]
                if text.exists && text.isHittable { text.tap(); return label }
            }
            hold(0.5)
        } while Date() < deadline
        return nil
    }

    /// iOS permission alerts sit over the app in Springboard
    private func answerSystemAlert() {
        for label in ["Allow While Using App", "Allow Once", "Allow", "Don’t Allow", "Not Now", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.5) { button.tap(); hold(1); return }
        }
    }

    func testNewUserFirstRun() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NEW_USER_WALKTHROUGH"] == "1")
        app.launch()
        mark("launch")
        hold(6)

        // The first-run chain: each screen gets a look, then the kindest
        // "go on" it offers. Up to 12 screens; the tour bubbles come after.
        var seen: [String] = []
        for _ in 0..<12 {
            answerSystemAlert()
            // A text field asking for a name
            let field = app.textFields.firstMatch
            if field.exists && field.isHittable && app.staticTexts["What should we call you?"].exists {
                field.tap(); field.typeText("Sim Tester"); hold(0.5)
            }
            if app.staticTexts["Explore other people's maps 🗺️"].exists { mark("people-sheet"); hold(4) }
            if let tapped = tapFirst(["Continue", "Not now", "Not Now", "Skip for now", "Maybe later", "Keep going", "Done", "Got it", "Allow", "Turn on", "Save", "Next"], wait: 6) {
                seen.append(tapped); mark("tapped \(tapped)"); hold(2.5)
            } else {
                break
            }
            // The home tour has begun: stop the generic loop
            if app.staticTexts["1 of 4"].exists { break }
        }
        print("WALK screens: \(seen)")

        // The tour: every bubble, Next each time, Keep going after the basics
        mark("tour")
        var bubbles = 0
        for _ in 0..<20 {
            answerSystemAlert()
            guard let tapped = tapFirst(["Next", "Keep going", "Done"], wait: 10) else { break }
            bubbles += 1
            mark("bubble \(bubbles) via \(tapped)")
            hold(2.5)
            if tapped == "Done" { break }
        }
        print("WALK bubbles: \(bubbles)")
        XCTAssertGreaterThanOrEqual(bubbles, 14, "the four basics, Keep going, and the ten extras")
        hold(3)
        mark("end")
    }
}
