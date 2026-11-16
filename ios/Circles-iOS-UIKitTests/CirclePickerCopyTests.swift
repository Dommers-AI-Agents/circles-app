import Testing
@testable import Circles_iOS

struct CirclePickerCopyTests {
    @Test func saysWhyBeforeAsking() {
        #expect(CirclePickerCopy.headline(forMove: false) == "Where should this place live?")
        #expect(CirclePickerCopy.headline(forMove: true) == "Where should it live now?")
        #expect(CirclePickerCopy.explanation(forMove: false, circleCount: 3).contains("Pick the one this place belongs in, or start a new one"))
        #expect(CirclePickerCopy.explanation(forMove: false, circleCount: 0).contains("Start your first one"))
        #expect(CirclePickerCopy.explanation(forMove: true, circleCount: 3).contains("A place lives in one at a time"))
        #expect(CirclePickerCopy.info.contains("move it to another circle any time"))
    }

    /// "Circle" never stands alone where someone new meets it (Wes, 2026-11-16)
    @Test func circleIsAlwaysPairedWithList() {
        #expect(CirclePickerCopy.pairedTitle == "Pick a circle · a list of places")
        for count in [0, 3] {
            #expect(CirclePickerCopy.explanation(forMove: false, circleCount: count).hasPrefix("Circles are your lists of places"))
        }
        #expect(CirclePickerCopy.explanation(forMove: true, circleCount: 3).hasPrefix("Circles are your lists of places"))
    }
}
