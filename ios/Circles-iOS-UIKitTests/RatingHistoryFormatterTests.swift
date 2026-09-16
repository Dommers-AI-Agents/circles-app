import Testing
import Foundation
@testable import Circles_iOS

/// "Latest wins, history kept" wording on the place page and the
/// post-check-in re-rate gate.
struct RatingHistoryFormatterTests {
    private func entry(_ r: Int) -> RatingHistoryEntry { RatingHistoryEntry(rating: r, at: nil, checkInId: nil) }

    @Test func unratedIsNil() {
        #expect(RatingHistoryFormatter.summary(current: nil, history: [entry(7)]) == nil)
    }

    @Test func singleRatingIsJustTheScore() {
        #expect(RatingHistoryFormatter.summary(current: 9, history: nil) == "9/10")
        #expect(RatingHistoryFormatter.summary(current: 9, history: [entry(9)]) == "9/10")
    }

    @Test func movedRatingShowsWhereItStarted() {
        #expect(RatingHistoryFormatter.summary(current: 9, history: [entry(7), entry(8), entry(9)]) == "9/10 · was 7 (3 ratings)")
    }

    @Test func unchangedHistoryShowsOnlyTheCount() {
        #expect(RatingHistoryFormatter.summary(current: 8, history: [entry(8), entry(8)]) == "8/10 (2 ratings)")
    }

    @Test func recheckSubtitle() {
        #expect(RatingHistoryFormatter.recheckSubtitle(current: nil) == "Tap a rating, or skip")
        #expect(RatingHistoryFormatter.recheckSubtitle(current: 7).hasPrefix("Your rating so far: 7/10"))
    }

    @Test func freshRatingSuppressesThePrompt() {
        let now = Date()
        #expect(RatingHistoryFormatter.shouldPromptAfterCheckIn(userRatedAt: nil, now: now))
        #expect(!RatingHistoryFormatter.shouldPromptAfterCheckIn(userRatedAt: now.addingTimeInterval(-600), now: now))
        #expect(RatingHistoryFormatter.shouldPromptAfterCheckIn(userRatedAt: now.addingTimeInterval(-3 * 3600), now: now))
    }
}
