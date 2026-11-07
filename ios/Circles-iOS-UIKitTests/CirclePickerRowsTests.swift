import Foundation
import Testing
@testable import Circles_iOS

/// The circle picker sheet's copy and search rule (2026-11-07 redesign)
struct CirclePickerRowsTests {
    @Test func detailSaysCountAndPrivacy() {
        #expect(CirclePickerRows.detail(placeCount: 1, privacy: .private) == "1 place · Private")
        #expect(CirclePickerRows.detail(placeCount: 0, privacy: .public) == "0 places · Public")
        #expect(CirclePickerRows.detail(placeCount: 12, privacy: .unknown).hasPrefix("12 places"))
    }

    @Test func searchOnlyOnceThereAreEnoughCircles() {
        #expect(!CirclePickerRows.showsSearch(circleCount: 3))
        #expect(CirclePickerRows.showsSearch(circleCount: CirclePickerRows.searchThreshold))
    }
}
