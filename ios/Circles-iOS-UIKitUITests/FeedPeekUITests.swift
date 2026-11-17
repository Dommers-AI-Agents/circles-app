import XCTest

/// Gets a signed-in simulator past the first-run sheets to the Home Activity
/// tab and holds there, then scrolls slowly, so `simctl io recordVideo` can
/// film the lively feed (2026-11-16). Skipped unless FEED_PEEK=1.
final class FeedPeekUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() { continueAfterFailure = true }

    private func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func answerSystemAlert() {
        for label in ["Allow While Using App", "Allow Once", "Allow", "Don’t Allow", "Not Now", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.0) { button.tap(); hold(0.8); return }
        }
    }

    @discardableResult
    private func tapFirst(_ labels: [String], wait: Double = 3) -> String? {
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for label in labels {
                let button = app.buttons[label]
                if button.exists && button.isHittable { button.tap(); return label }
                let text = app.staticTexts[label]
                if text.exists && text.isHittable { text.tap(); return label }
            }
            hold(0.4)
        } while Date() < deadline
        return nil
    }

    func testPeekAtTheFeed() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FEED_PEEK"] == "1")
        app.launch()
        hold(4)
        // Through whatever first-run sheets a fresh install shows
        for _ in 0..<8 {
            answerSystemAlert()
            guard tapFirst(["Not now", "Not Now", "Skip", "Skip for now", "Maybe later", "Done", "Got it", "Continue"], wait: 2) != nil else { break }
            hold(1.5)
        }
        answerSystemAlert()
        // The Activity segment, if the home isn't on it already
        if app.buttons["Activity"].exists { app.buttons["Activity"].tap() }
        hold(6)
        // The feed sits under the map: bring the page up to it first
        for _ in 0..<2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.1, thenDragTo: end)
            hold(2.5)
        }
        // Then slowly through the feed so the rows get their entrance
        for _ in 0..<6 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.1, thenDragTo: end)
            hold(4)
        }
        hold(2)
    }
}
