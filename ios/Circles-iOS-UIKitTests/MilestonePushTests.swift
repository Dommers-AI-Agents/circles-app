import Testing
import Foundation
@testable import Circles_iOS

/// A milestone push ("🥈 Second place!") lands on its screen, even from a cold start.
struct MilestonePushTests {

    @Test func topContributorPushRoutesWithItsPosition() {
        let info: [AnyHashable: Any] = ["type": "milestone", "milestoneType": "top_contributor", "position": "2", "placeCount": "14"]
        #expect(NotificationTapRouter.destination(for: info) == .milestone(PushMilestone(kind: "top_contributor", value: 14, position: 2)))
    }

    @Test func countMilestonesRouteToo() {
        let info: [AnyHashable: Any] = ["type": "milestone", "data": ["milestoneType": "connections", "milestoneValue": "10"]]
        #expect(NotificationTapRouter.destination(for: info) == .milestone(PushMilestone(kind: "connections", value: 10, position: nil)))
        #expect(NotificationTapRouter.destination(for: ["type": "milestone"]) == .milestone(PushMilestone(kind: "places", value: nil, position: nil)))
    }

    @Test func survivesTheColdStartStash() {
        let m = PushMilestone(kind: "top_contributor", value: 14, position: 2)
        #expect(m.pendingLink == "milestone:top_contributor:14:2")
        #expect(PendingLinkParser.parse(m.pendingLink) == .milestone(m))
        let bare = PushMilestone(kind: "places", value: nil, position: nil)
        #expect(PendingLinkParser.parse(bare.pendingLink) == .milestone(bare))
    }

    @Test func wordsReadNaturally() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 112].map(MilestoneCopy.ordinal) == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st", "112th"])
        let second = PushMilestone(kind: "top_contributor", value: 14, position: 2)
        #expect(MilestoneCopy.headline(second, month: nil) == "2nd for adding places this month")
        #expect(MilestoneCopy.headline(second, month: (15, 1)) == "1st for adding places this month")
        #expect(MilestoneCopy.detail(second, count: 14, behindFirst: 3) == "You added 14 places in the last 30 days. 3 more and you'd tie for first.")
        #expect(MilestoneCopy.emoji(second) == "🥈")
        #expect(MilestoneCopy.primaryPath(PushMilestone(kind: "connections", value: 5, position: nil)) == "network")
    }
}
