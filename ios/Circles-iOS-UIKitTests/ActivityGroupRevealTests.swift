import Testing
import UIKit
@testable import Circles_iOS

/// Opening a group of activities scrolls them into view under a peek of the
/// group's card — a photo card is as tall as the feed, so the activities used
/// to open below the fold (Wes, 2026-11-24).
struct ActivityGroupRevealTests {

    private typealias Feed = HomeActivityFeedViewController
    private let noInsets = UIEdgeInsets.zero

    @Test func aTallPhotoCardScrollsUpToItsCaption() {
        // Card at 300…900, activities start at 900, plenty of list below
        let y = Feed.revealOffset(headerRect: CGRect(x: 0, y: 300, width: 400, height: 600),
                                  firstChildMinY: 900, contentHeight: 5000,
                                  visibleHeight: 700, insets: noInsets)
        #expect(y == 900 - Feed.revealHeaderPeek)
    }

    @Test func aShortSummaryRowStaysWholeAboveItsActivities() {
        let y = Feed.revealOffset(headerRect: CGRect(x: 0, y: 300, width: 400, height: 70),
                                  firstChildMinY: 370, contentHeight: 5000,
                                  visibleHeight: 700, insets: noInsets)
        #expect(y == 300)
    }

    @Test func neverScrollsPastTheEndOfTheList() {
        let y = Feed.revealOffset(headerRect: CGRect(x: 0, y: 300, width: 400, height: 600),
                                  firstChildMinY: 900, contentHeight: 1200,
                                  visibleHeight: 700, insets: UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0))
        let end: CGFloat = 1200 + 80 - 700
        #expect(y == end)
    }

    @Test func aListShorterThanTheScreenStaysAtTheTop() {
        let y = Feed.revealOffset(headerRect: CGRect(x: 0, y: 0, width: 400, height: 70),
                                  firstChildMinY: 70, contentHeight: 300,
                                  visibleHeight: 700, insets: UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0))
        #expect(y == -12)
    }
}
