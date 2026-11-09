import Testing
import Foundation
@testable import Circles_iOS

/// After a visit: a 0–10 FavCircles rating, then one next step.
struct PostVisitRatingRuleTests {

    private typealias R = PostVisitRatingRule

    @Test func sevenAndUpRecommendsFourAndUnderGoesPrivate() {
        #expect(R.next(for: 10) == .recommend)
        #expect(R.next(for: 7) == .recommend)
        #expect(R.next(for: 6) == .none)
        #expect(R.next(for: 5) == .none)
        #expect(R.next(for: 4) == .tellPrivately)
        #expect(R.next(for: 0) == .tellPrivately)
    }

    @Test func regularsAreAskedAgainAfterThirtyDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(R.shouldAskAgain(userRatedAt: nil, now: now))
        #expect(!R.shouldAskAgain(userRatedAt: now.addingTimeInterval(-29 * 86400), now: now))
        #expect(R.shouldAskAgain(userRatedAt: now.addingTimeInterval(-31 * 86400), now: now))
    }

    @Test func promptsAndFollowUpsNameTheStore() {
        #expect(R.prompt(storeName: "Sal's", firstTime: true) == "How would you rate Sal's?")
        #expect(R.prompt(storeName: "Sal's", firstTime: false) == "How was Sal's this time?")
        #expect(R.followUp(.recommend, storeName: "Sal's")?.contains("review") == true)
        #expect(R.followUp(.tellPrivately, storeName: "Sal's")?.contains("privately") == true)
        #expect(R.followUp(.none, storeName: "Sal's") == nil)
    }
}
