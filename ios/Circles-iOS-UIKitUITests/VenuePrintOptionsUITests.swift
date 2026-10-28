import XCTest

/// End to end on a signed-in super-user account: profile → store icon →
/// Sticker Venues → a store → Register Card QR → Share or Print → Print a sign
/// or tent… → Share or Print PDF → the share sheet opens with a real PDF.
/// Writes `<name>.ready` markers into tmp/duo-capture and holds 8 s on each,
/// so a shell loop on the Mac can screenshot the device at those moments.
final class VenuePrintOptionsUITests: XCTestCase {
    private let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("duo-capture", isDirectory: true)

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func mark(_ name: String) {
        FileManager.default.createFile(atPath: dir.appendingPathComponent("\(name).ready").path, contents: Data())
        sleep(8)
    }

    func testPrintSheetHandsOverAPDF() throws {
        let app = XCUIApplication()
        app.launch()
        for label in ["Allow", "Continue", "Not now", "Not Now", "Skip", "Later", "Done"] {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: 2) { b.tap(); sleep(1) }
        }

        let me = app.buttons["Me"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20)); me.tap(); sleep(2); me.tap()
        let storefront = app.buttons["My Storefront"].firstMatch
        XCTAssertTrue(storefront.waitForExistence(timeout: 15)); storefront.tap()

        // Super-user: the Sticker Venues list. Pick the first real store.
        let list = app.navigationBars["Sticker Venues"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let row = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Tommy' OR label CONTAINS[c] 'Fresh'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()

        let registerRow = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Register'")).firstMatch
        XCTAssertTrue(registerRow.waitForExistence(timeout: 15)); registerRow.tap()

        let share = app.buttons["Share or Print"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15)); share.tap()
        let printChoice = app.buttons["Print a sign or tent…"].firstMatch
        XCTAssertTrue(printChoice.waitForExistence(timeout: 10)); printChoice.tap()

        let tent = app.buttons["Table tent"].firstMatch
        XCTAssertTrue(tent.waitForExistence(timeout: 10)); tent.tap()
        let large = app.buttons["4 in"].firstMatch
        XCTAssertTrue(large.waitForExistence(timeout: 5)); large.tap()
        mark("print-sheet")

        app.buttons["Share or Print PDF"].firstMatch.tap()
        // The share sheet: Apple's activity view, which lists Print among its rows
        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 60), "share sheet with the PDF")
        mark("share-sheet")
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
