import XCTest

/// Helper for recording the tutorial video (Marketing/tutorial-2026-11):
/// prints the Home element tree so the recording test can target controls.
/// Run only on purpose (it's skipped unless TOUR_PROBE=1).
final class TutorialRecordingProbe: XCTestCase {
    func testDumpHome() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOUR_PROBE"] == "1")
        let app = XCUIApplication()
        app.activate()
        if app.buttons["Continue"].waitForExistence(timeout: 5) { app.buttons["Continue"].tap() }
        sleep(4)
        print("PROBE-BEGIN")
        print(app.debugDescription)
        print("PROBE-END")
    }
}
