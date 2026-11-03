import Testing
import Foundation
@testable import Circles_iOS

/// Private feedback to a store (2026-11-02): the push opens the store's
/// feedback screen, warm or cold, and the rows read right.
struct StoreFeedbackTests {

    @Test func pushOpensTheStoresFeedback() {
        #expect(NotificationTapRouter.destination(for: ["type": "store_feedback", "venueId": "v1"]) == .venueFeedback(venueId: "v1"))
        #expect(NotificationTapRouter.destination(for: ["type": "store_feedback"]) == nil)
        #expect(PendingLinkParser.parse("venue-feedback:v1") == .venueFeedback(venueId: "v1"))
    }

    @Test func rowWords() {
        let entry = StoreFeedbackEntry(rating: 4, note: "Great smoothies", createdAt: nil,
                                       user: .init(id: "u1", displayName: "Ann", profilePicture: nil))
        #expect(StoreFeedbackCopy.headline(entry) == "\u{2605}\u{2605}\u{2605}\u{2605}\u{2606} Ann")
        #expect(StoreFeedbackCopy.detail(entry) == "Great smoothies")
        let anon = StoreFeedbackEntry(rating: 9, note: nil, createdAt: nil, user: nil)
        #expect(StoreFeedbackCopy.headline(anon) == "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605} A customer")
    }
}
