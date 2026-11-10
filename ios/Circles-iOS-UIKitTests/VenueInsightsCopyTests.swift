import Testing
import Foundation
@testable import Circles_iOS

/// The owner's Insights page wording: score, trend, Google beside it,
/// customer tiles, repeat rate, reviews waiting.
struct VenueInsightsCopyTests {

    private typealias C = VenueInsightsCopy

    @Test func scoreReadsAsOutOfTen() {
        #expect(C.scoreLine(average: 8.4) == "8.4 / 10")
        #expect(C.scoreLine(average: 9) == "9 / 10")
        #expect(C.scoreLine(average: nil) == "No ratings yet")
    }

    @Test func scoreCaptionCountsRatingsAndRecommendations() {
        #expect(C.scoreCaption(ratings: 12, recommend: 9, recommendPct: 75) == "12 ratings · 9 recommend it (75%)")
        #expect(C.scoreCaption(ratings: 1, recommend: 0, recommendPct: 0) == "1 rating")
        #expect(C.scoreCaption(ratings: 0, recommend: 0, recommendPct: nil).contains("rate it 0–10"))
    }

    @Test func trendIsSteadyNearZeroAndSignedOtherwise() {
        #expect(C.trendLine(nil) == nil)
        #expect(C.trendLine(0.0) == "Steady vs. the 30 days before")
        #expect(C.trendLine(0.3) == "+0.3 vs. the 30 days before")
        #expect(C.trendLine(-1.2) == "−1.2 vs. the 30 days before")
    }

    @Test func googleRatingStaysBesideTheScore() {
        #expect(C.googleLine(rating: 4.6, total: 212) == "Google 4.6★ · 212 reviews")
        #expect(C.googleLine(rating: 5, total: 1) == "Google 5.0★ · 1 review")
        #expect(C.googleLine(rating: 4.2, total: 0) == "Google 4.2★")
        #expect(C.googleLine(rating: nil, total: 10) == nil)
    }

    @Test func customerTilesNameThePeriodForNewAndReturning() {
        let customers = VenueInsightsData.Customers(visits: 40, visitors: 18, newCustomers: 7, returningCustomers: 11,
                                                    total: 30, repeatRatePct: 60, regulars: 9, lapsed: 4)
        let tiles = C.customerTiles(customers, range: .days90)
        #expect(tiles.map(\.title) == ["New customers", "Came back", "Regulars", "Haven't been back"])
        #expect(tiles.map(\.value) == [7, 11, 9, 4])
        #expect(tiles[0].caption.hasSuffix("in the last 90 days"))
        #expect(tiles[3].caption == "No purchase in 30 days")
    }

    @Test func referredLineOnlyWhenSomeoneCame() {
        #expect(VenueInsightsCopy.referredLine(nil) == nil)
        #expect(VenueInsightsCopy.referredLine(0) == nil)
        #expect(VenueInsightsCopy.referredLine(1) == "1 new customer came through a friend's invite")
        #expect(VenueInsightsCopy.referredLine(3) == "3 new customers came through a friend's invite")
    }

    @Test func repeatAndVisitsLines() {
        #expect(C.repeatLine(pct: 60, total: 30) == "60% of your 30 customers have bought here more than once")
        #expect(C.repeatLine(pct: nil, total: 0).contains("Repeat rate shows"))
        #expect(C.visitsLine(visits: 1, visitors: 1, range: .days30) == "1 purchase by 1 person in the last 30 days")
        #expect(C.visitsLine(visits: 0, visitors: 0, range: .months12) == "No register scans in the last 12 months")
    }

    @Test func reviewsWaitingForAReply() {
        #expect(C.awaitingLine(count: 0) == "Every review has a reply from you")
        #expect(C.awaitingLine(count: 1) == "1 review is waiting for a reply")
        #expect(C.awaitingLine(count: 3) == "3 reviews are waiting for a reply")
        #expect(C.commentsLine(inPeriod: 2, total: 9, range: .days30) == "2 new in the last 30 days · 9 in all")
        #expect(C.commentsLine(inPeriod: 0, total: 0, range: .days30).contains("No reviews on FavCircles yet"))
    }

    @Test func rangesMatchTheServer() {
        #expect(C.Range.allCases.map(\.rawValue) == ["30d", "90d", "12m"])
        #expect(C.Range.allCases.map(\.title) == ["30 days", "90 days", "12 months"])
    }
}
