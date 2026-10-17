import XCTest

/// Build my map from my photos, end to end on a seeded simulator (geotagged
/// test photos, a throwaway account): the sign-up step, the build, the free
/// limit. Screenshots are kept as attachments.
final class PhotoMapBuilderUITests: XCTestCase {
    func testBuildMyMapFromPhotos() throws {
        let app = XCUIApplication()
        app.launch()
        snap(app, "01-launch")

        // Past whatever first-run screens are up, to Home
        for label in ["Continue", "Not now", "Skip", "Done"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 4) { button.tap(); sleep(2) }
        }
        sleep(4)
        snap(app, "02-home-before")

        // Add Place menu → Build my map from my photos
        let addPlace = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Place'")).firstMatch
        XCTAssertTrue(addPlace.waitForExistence(timeout: 20), "Add Place on Home")
        addPlace.tap()
        let menuItem = app.buttons["Build my map from my photos"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "menu item")
        menuItem.tap()
        let build = app.buttons["Build my map"]
        XCTAssertTrue(build.waitForExistence(timeout: 10), "builder intro")
        snap(app, "03-intro")
        build.tap()
        // The system's photo-library prompt
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow Full Access"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        // Working…
        sleep(20)
        snap(app, "03-working")

        // The free limit (25) or done
        let premium = app.buttons["Add the rest with Premium"]
        let seeMap = app.buttons["See my map"]
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline && !premium.exists && !seeMap.exists { sleep(5) }
        snap(app, "04-limit-or-done")
        XCTAssertTrue(premium.exists || seeMap.exists)
        if premium.exists {
            premium.tap()
            sleep(4)
            snap(app, "05-paywall")
            app.swipeDown(velocity: .fast)
            sleep(2)
        }
        if seeMap.waitForExistence(timeout: 10) { seeMap.tap() }
        sleep(4)
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 8) { notNow.tap() }
        sleep(8)
        snap(app, "06-home")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
