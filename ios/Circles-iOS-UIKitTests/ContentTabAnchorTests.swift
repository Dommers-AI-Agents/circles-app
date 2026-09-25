import Testing
import CoreGraphics
@testable import Circles_iOS

struct ContentTabAnchorTests {
    /// iPhone-ish: 750pt visible under the nav bar, section at y=380 in the
    /// content, 90pt of header + segment bar above the slot.
    @Test func slotFillsWhatIsLeftUnderTheBarAndTheSectionPinsToTheTop() {
        let layout = ContentTabAnchor.layout(visibleHeight: 750, sectionTop: 380, chromeHeight: 90, topInset: 100)
        #expect(layout.slotHeight == 660)
        #expect(layout.contentOffsetY == 280) // section top minus the nav inset
    }

    @Test func aDailyCardAboveTheSlotCountsAsChrome() {
        let without = ContentTabAnchor.layout(visibleHeight: 750, sectionTop: 380, chromeHeight: 90, topInset: 100)
        let with = ContentTabAnchor.layout(visibleHeight: 750, sectionTop: 380, chromeHeight: 90 + 120, topInset: 100)
        #expect(with.slotHeight == without.slotHeight - 120)
        #expect(with.contentOffsetY == without.contentOffsetY)
    }

    @Test func theReelIsNeverSquashedBelowTheMinimum() {
        let layout = ContentTabAnchor.layout(visibleHeight: 300, sectionTop: 0, chromeHeight: 90, topInset: 0)
        #expect(layout.slotHeight == 320)
    }

    @Test func fractionalHeightsRoundDownSoPagesNeverOvershoot() {
        let layout = ContentTabAnchor.layout(visibleHeight: 750.6, sectionTop: 0, chromeHeight: 90.3, topInset: 0)
        #expect(layout.slotHeight == 660)
    }
}
