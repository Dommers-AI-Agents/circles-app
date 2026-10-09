import Testing
@testable import Circles_iOS

/// "Include on my map" says what each position means — off still alerts.
struct CircleMapCopyTests {
    @Test func offExplainsTheAlertsAndHowToStopThem() {
        #expect(CircleMapCopy.note(isOn: true) == CircleMapCopy.onNote)
        let off = CircleMapCopy.note(isOn: false)
        #expect(off.contains("friends' maps"))
        #expect(off.contains("Alert Me at Saved Places"))
    }
}
