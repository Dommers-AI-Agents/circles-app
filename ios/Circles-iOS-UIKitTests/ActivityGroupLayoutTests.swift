import Testing
import UIKit
@testable import Circles_iOS

/// A small burst of one person's activities is one card you swipe through;
/// a big one keeps "Show all" and opens into full cards (Wes, 2026-11-24).
@MainActor
struct ActivityGroupLayoutTests {
    typealias FeedItem = HomeActivityFeedViewController.FeedItem

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func activity(_ id: String, minutesAgo: Double = 0, type: ActivityType = .placeAdded) -> Activity {
        Activity(id: id, type: type, actorId: "amy", actor: nil, targetType: "place", targetId: "t-\(id)",
                 targetName: id, circleId: nil, circleName: nil, metadata: nil,
                 timestamp: base.addingTimeInterval(-minutesAgo * 60), isRead: nil,
                 reactionCount: nil, commentCount: nil, userReaction: nil, reactionSummary: nil)
    }

    private func burst(_ count: Int) -> [Activity] {
        (0..<count).map { activity("a\($0)", minutesAgo: Double($0)) }
    }

    private func describe(_ items: [FeedItem]) -> [String] {
        items.map {
            switch $0 {
            case .single(let a): return "single:\(a.id)"
            case .group(let g): return "group:\(g.count)"
            case .groupChild(let a): return "child:\(a.id)"
            }
        }
    }

    // MARK: The rule

    @Test func aFewActivitiesAreSwipedAndManyAreOpened() {
        #expect(ActivityGroupLayout.layout(count: 2, enabled: true) == .pages)
        #expect(ActivityGroupLayout.layout(count: ActivityGroupLayout.maxPages, enabled: true) == .pages)
        #expect(ActivityGroupLayout.layout(count: ActivityGroupLayout.maxPages + 1, enabled: true) == .expandable)
        #expect(ActivityGroupLayout.layout(count: 40, enabled: true) == .expandable)
    }

    @Test func switchedOffEveryGroupIsTheOldStack() {
        #expect(ActivityGroupLayout.layout(count: 2, enabled: false) == nil)
        #expect(ActivityGroupLayout.layout(count: 40, enabled: false) == nil)
    }

    @Test func theRememberedPageStaysInsideTheBurst() {
        #expect(ActivityGroupLayout.page(nil, count: 3) == 0)
        #expect(ActivityGroupLayout.page(2, count: 3) == 2)
        // An activity was deleted since: the last page that still exists
        #expect(ActivityGroupLayout.page(4, count: 3) == 2)
        #expect(ActivityGroupLayout.page(-1, count: 3) == 0)
        #expect(ActivityGroupLayout.page(1, count: 0) == 0)
    }

    @Test func swipingStopsAtEitherEnd() {
        #expect(ActivityGroupLayout.page(after: 0, count: 3, forward: true) == 1)
        #expect(ActivityGroupLayout.page(after: 1, count: 3, forward: false) == 0)
        #expect(ActivityGroupLayout.page(after: 2, count: 3, forward: true) == nil)
        #expect(ActivityGroupLayout.page(after: 0, count: 3, forward: false) == nil)
    }

    // MARK: The feed's rows

    @Test func aSwipeableBurstNeverOpensRowsUnderIt() {
        let feed = burst(3)
        let rows = HomeActivityFeedViewController.group(feed, expandedKeys: ["a0"], pagesSmallGroups: true)
        #expect(describe(rows) == ["group:3"])
    }

    @Test func aBigBurstStillOpens() {
        let feed = burst(7)
        let rows = HomeActivityFeedViewController.group(feed, expandedKeys: ["a0"], pagesSmallGroups: true)
        #expect(describe(rows) == ["group:7"] + (0..<7).map { "child:a\($0)" })
    }

    @Test func switchedOffASmallBurstOpensItsRowsAsBefore() {
        let rows = HomeActivityFeedViewController.group(burst(3), expandedKeys: ["a0"])
        #expect(describe(rows) == ["group:3", "child:a0", "child:a1", "child:a2"])
    }

    // MARK: The card

    @Test func eachSwipeIsOneWholeActivity() {
        let feed = burst(3)
        let cell = ActivityHeroCell(style: .default, reuseIdentifier: nil)
        var reported: [Int] = []
        cell.onPageChange = { reported.append($0) }
        cell.configure(pages: feed, index: 0)
        #expect(cell.currentActivity?.id == "a0")

        #expect(cell.turnPage(forward: true))
        #expect(cell.currentActivity?.id == "a1")
        #expect(cell.turnPage(forward: true))
        #expect(cell.currentActivity?.id == "a2")
        // The last page: nothing further, and the feed isn't told of a change
        #expect(!cell.turnPage(forward: true))
        #expect(cell.currentActivity?.id == "a2")
        #expect(cell.turnPage(forward: false))
        #expect(cell.currentActivity?.id == "a1")
        #expect(reported == [1, 2, 1])
    }

    @Test func theCardComesBackOnThePageItWasLeftOn() {
        let cell = ActivityHeroCell(style: .default, reuseIdentifier: nil)
        cell.configure(pages: burst(3), index: 2)
        #expect(cell.currentActivity?.id == "a2")
        #expect(cell.pageIndex == 2)
    }

    @Test func aSingleActivityCardDoesNotPage() {
        let cell = ActivityHeroCell(style: .default, reuseIdentifier: nil)
        cell.configure(pages: burst(3), index: 1)
        let one = activity("solo")
        cell.configure(activity: one, hero: .poster(ActivityRowStyle.poster(for: one)))
        #expect(!cell.turnPage(forward: true))
        #expect(cell.currentActivity?.id == "solo")
    }
}
