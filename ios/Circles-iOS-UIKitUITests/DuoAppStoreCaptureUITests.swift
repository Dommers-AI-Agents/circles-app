import XCTest

/// A tap servant for the App Store capture run on the iPhone Duo simulator.
///
/// The Mac side (Marketing capture script) drives navigation with
/// `simctl openurl` and takes the screenshots with `simctl io screenshot`
/// (the only way to capture the Duo's inner display). This test only performs
/// the taps a deep link cannot: it launches the app, then polls a command file
/// in its own tmp folder (visible on the Mac in the runner's data container)
/// and runs each command, answering with `<command>.done`.
///
/// Commands: `expand-map`, `close-map`, `store-points`, `privacy`, `end`.
/// Run with `-parallel-testing-enabled NO` so the app stays on the device being captured.
final class DuoAppStoreCaptureUITests: XCTestCase {
    private let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("duo-capture", isDirectory: true)

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func testServeCommands() throws {
        let app = XCUIApplication()
        app.launch()
        dismissPrompts(app)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("launched").path, contents: Data())

        let cmdFile = dir.appendingPathComponent("cmd").path
        let started = Date()
        while Date().timeIntervalSince(started) < 1500 {   // 25 minutes of service
            guard let cmd = try? String(contentsOfFile: cmdFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  !cmd.isEmpty else { usleep(500_000); continue }
            try? FileManager.default.removeItem(atPath: cmdFile)
            if cmd == "end" { break }
            run(cmd, app)
            FileManager.default.createFile(atPath: dir.appendingPathComponent("\(cmd).done").path, contents: Data())
        }
    }

    private func run(_ cmd: String, _ app: XCUIApplication) {
        switch cmd {
        case "expand-map":
            let expand = app.buttons.matching(NSPredicate(format: "label == 'arrow.up.left.and.arrow.down.right' OR identifier == 'mapExpandButton'")).firstMatch
            if expand.waitForExistence(timeout: 5) { expand.tap() }
        case "close-map":
            let close = app.buttons.matching(NSPredicate(format: "label == 'xmark.circle.fill' OR label == 'Close'")).firstMatch
            if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown() }
        case "store-points":
            let b = app.buttons["Store Points"].firstMatch
            if b.waitForExistence(timeout: 5) { b.tap() }
        case "privacy":
            let me = app.buttons["Me"].firstMatch
            if me.waitForExistence(timeout: 4) { me.tap(); sleep(2); me.tap(); sleep(3) }   // second tap pops to the profile root
            run("dump", app)
            let gear = app.buttons.matching(NSPredicate(format: "label == 'gear' OR label == 'Settings' OR label CONTAINS[c] 'settings'")).firstMatch
            if gear.waitForExistence(timeout: 5) { gear.tap(); sleep(2) }
            tapRow(app, "Privacy")
            tapRow(app, "Who can see my activity")
        case "dismiss":
            dismissPrompts(app)
        case "locate":
            let b = app.buttons.matching(NSPredicate(format: "label == 'Tracking' OR label CONTAINS[c] 'location' OR label CONTAINS[c] 'near me'")).firstMatch
            if b.waitForExistence(timeout: 4) { b.tap() }
        case "dump":
            var lines: [String] = []
            for b in app.buttons.allElementsBoundByIndex.prefix(80) { lines.append("button|\(b.label)|\(b.identifier)|\(b.frame)") }
            for b in app.navigationBars.buttons.allElementsBoundByIndex { lines.append("navbutton|\(b.label)|\(b.identifier)|\(b.frame)") }
            for c in app.cells.allElementsBoundByIndex.prefix(40) { lines.append("cell|\(c.label)|\(c.identifier)") }
            try? lines.joined(separator: "\n").write(toFile: dir.appendingPathComponent("dump-\(Int(Date().timeIntervalSince1970)).txt").path, atomically: true, encoding: .utf8)
        default:
            break
        }
        sleep(2)
    }

    private func dismissPrompts(_ app: XCUIApplication) {
        for label in ["Allow While Using App", "Allow", "Continue", "Not now", "Not Now", "Skip", "Later", "Done"] {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: 2) { b.tap(); sleep(1) }
        }
    }

    private func tapRow(_ app: XCUIApplication, _ label: String) {
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        let text = app.staticTexts[label].firstMatch
        if cell.waitForExistence(timeout: 4) { cell.tap() }
        else if text.waitForExistence(timeout: 2) { text.tap() }
        sleep(2)
    }
}
