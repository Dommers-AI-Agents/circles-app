import Testing
import Foundation
@testable import Circles_iOS

/// The Activity tab's row derivation: consecutive same-actor activities
/// within an hour collapse into one group row; check-ins never group; an
/// expanded group also emits its members as child rows.
struct HomeActivityFeedGroupingTests {
    typealias FeedItem = HomeActivityFeedViewController.FeedItem

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Feed is newest-first: `minutesAgo` grows down the list.
    private func activity(_ id: String, actor: String, minutesAgo: Double, type: ActivityType = .placeAdded) -> Activity {
        Activity(id: id, type: type, actorId: actor, actor: nil, targetType: "place", targetId: "t-\(id)",
                 targetName: id, circleId: nil, circleName: nil, metadata: nil,
                 timestamp: base.addingTimeInterval(-minutesAgo * 60), isRead: nil,
                 reactionCount: nil, commentCount: nil, userReaction: nil, reactionSummary: nil)
    }

    private func describe(_ items: [FeedItem]) -> [String] {
        items.map {
            switch $0 {
            case .single(let a): return "single:\(a.id)"
            case .group(let g): return "group:" + g.map { $0.id }.joined(separator: "+")
            case .groupChild(let a): return "child:\(a.id)"
            }
        }
    }

    @Test func burstBySameActorWithinAnHourCollapses() {
        let feed = [activity("a1", actor: "amy", minutesAgo: 0),
                    activity("a2", actor: "amy", minutesAgo: 10),
                    activity("a3", actor: "amy", minutesAgo: 50),
                    activity("b1", actor: "bob", minutesAgo: 60)]
        #expect(describe(HomeActivityFeedViewController.group(feed, expandedKeys: [])) == ["group:a1+a2+a3", "single:b1"])
    }

    @Test func windowIsRollingBetweenNeighbours() {
        // 55 minutes apart each: a1→a2 and a2→a3 both qualify even though a1→a3 is 110 min
        let feed = [activity("a1", actor: "amy", minutesAgo: 0),
                    activity("a2", actor: "amy", minutesAgo: 55),
                    activity("a3", actor: "amy", minutesAgo: 110),
                    activity("a4", actor: "amy", minutesAgo: 200)]   // 90 min after a3 → new run
        #expect(describe(HomeActivityFeedViewController.group(feed, expandedKeys: [])) == ["group:a1+a2+a3", "single:a4"])
    }

    @Test func aLoneActivityStaysSingle() {
        let feed = [activity("a1", actor: "amy", minutesAgo: 0),
                    activity("b1", actor: "bob", minutesAgo: 5),
                    activity("a2", actor: "amy", minutesAgo: 10)]
        #expect(describe(HomeActivityFeedViewController.group(feed, expandedKeys: [])) == ["single:a1", "single:b1", "single:a2"])
    }

    @Test func checkInsNeverGroupAndDontBreakTheSurroundingBurst() {
        let feed = [activity("a1", actor: "amy", minutesAgo: 0),
                    activity("c1", actor: "amy", minutesAgo: 5, type: .checkIn),
                    activity("a2", actor: "amy", minutesAgo: 10)]
        // The group is inserted back at the position of its newest member (a1)
        #expect(describe(HomeActivityFeedViewController.group(feed, expandedKeys: [])) == ["group:a1+a2", "single:c1"])
    }

    @Test func expandedGroupEmitsItsMembersAsChildRows() {
        let feed = [activity("a1", actor: "amy", minutesAgo: 0),
                    activity("a2", actor: "amy", minutesAgo: 10),
                    activity("b1", actor: "bob", minutesAgo: 20)]
        let out = HomeActivityFeedViewController.group(feed, expandedKeys: ["a1"])
        #expect(describe(out) == ["group:a1+a2", "child:a1", "child:a2", "single:b1"])
        #expect(describe(HomeActivityFeedViewController.group(feed, expandedKeys: ["a2"])) == ["group:a1+a2", "single:b1"], "keyed by the group's first activity only")
    }
}
