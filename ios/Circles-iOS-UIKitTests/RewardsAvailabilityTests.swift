import Testing
import Foundation
@testable import Circles_iOS

/// When the place page and the check-in confirmation offer "Get Rewards",
/// and what the Get Rewards page says.
struct RewardsAvailabilityTests {

    /// The by-place response as the server sends it; `extra` adds or
    /// overrides top-level fields.
    private func data(_ extra: String = "", venue: Bool = true) throws -> PlaceVenueData {
        let venueJSON = venue
            ? #""venue": {"venueId": "v1", "venueName": "Pasta & Provisions", "earnRate": 10}"#
            : #""venue": null"#
        let offers = #""offers": [{"offerId": "o2", "title": "Free dessert", "pointsCost": 50}, {"offerId": "o1", "title": "Free coffee", "pointsCost": 20}]"#
        let json = "{\(venueJSON), \(offers), \"venueBalance\": 30\(extra.isEmpty ? "" : ", " + extra)}"
        return try JSONDecoder().decode(PlaceVenueData.self, from: Data(json.utf8))
    }

    @Test func noVenueMeansNoRewards() throws {
        #expect(RewardsAvailability(try data(venue: false)) == .none)
        #expect(RewardsAvailability(nil) == .none)
    }

    @Test func liveVenueEarns() throws {
        let details = try #require(RewardsAvailability(try data(#""rewardsLive": true"#)).details)
        #expect(details.venueName == "Pasta & Provisions")
        #expect(details.earnRate == 10)
        #expect(details.venueBalance == 30)
        #expect(details.offers.map(\.title) == ["Free dessert", "Free coffee"])
    }

    @Test func pausedVenueOffersNothing() throws {
        // The owner's subscription lapsed: a scan would award nothing.
        #expect(RewardsAvailability(try data(#""rewardsLive": false"#)) == .none)
    }

    @Test func olderServerWithoutTheFieldCountsAsLive() throws {
        #expect(RewardsAvailability(try data()).details != nil)
    }

    @Test func theStoresOwnTeamDoesNotGetTheButton() throws {
        #expect(RewardsAvailability(try data(#""rewardsLive": true, "isOwner": true"#)) == .none)
    }

    @Test func copy() throws {
        let details = try #require(RewardsAvailability(try data()).details)
        #expect(RewardsAvailability.earnLine(details) == "Earn 10 points per visit")
        #expect(RewardsAvailability.balanceLine(details) == "You have 30 points here")
        #expect(RewardsAvailability.checkInNudge(details)
                == "Pasta & Provisions gives 10 points per visit. Scan the QR code at the register to collect them.")
    }

    @Test func storeCardSaysRewardsOnlyWhileTheyAreLive() {
        // Enrolled, no owner yet (or Business lapsed): the store by name, no earn line
        let unowned = RewardsAvailability.storeCardHeader(venueName: "Pasta & Provisions", isOwner: false, rewardsLive: false)
        #expect(unowned == .init(title: "Pasta & Provisions", showsEarnLine: false))
        let live = RewardsAvailability.storeCardHeader(venueName: "Pasta & Provisions", isOwner: false, rewardsLive: true)
        #expect(live == .init(title: "Rewards at Pasta & Provisions", showsEarnLine: true))
        // The owner's own store is always theirs; the earn line still waits for Business
        let owner = RewardsAvailability.storeCardHeader(venueName: "Pasta & Provisions", isOwner: true, rewardsLive: false)
        #expect(owner == .init(title: "Your Store · Pasta & Provisions", showsEarnLine: false))
    }

    @Test func balanceCopyCoversNoneAndOne() {
        func details(_ balance: Int) -> RewardsAvailability.Details {
            .init(venueName: "Shop", earnRate: nil, venueBalance: balance, offers: [])
        }
        #expect(RewardsAvailability.balanceLine(details(0)) == "You don't have any points here yet")
        #expect(RewardsAvailability.balanceLine(details(1)) == "You have 1 point here")
        #expect(RewardsAvailability.earnLine(details(5)) == nil)
        #expect(RewardsAvailability.checkInNudge(details(0))
                == "Shop has rewards. Scan the QR code at the register to collect them.")
    }

    // MARK: - Next reward (the progress card that replaced "type a code")

    private func details(balance: Int, rate: Int? = 25, offers: [(String, Int)] = [("Free drip coffee", 100), ("Free croissant with any latte", 150)]) -> RewardsAvailability.Details {
        RewardsAvailability.Details(venueName: "Test Bakery", earnRate: rate, venueBalance: balance,
                                    offers: offers.map { RewardsAvailability.Offer(title: $0.0, pointsCost: $0.1) })
    }

    @Test func nextRewardIsTheCheapestStillOutOfReach() {
        let r = RewardsAvailability.nextReward(details(balance: 25))!
        #expect(r.title == "Free drip coffee")
        #expect(r.remaining == 75)
        #expect(r.visitsLeft == 3)
        #expect(abs(r.fraction - 0.25) < 0.001)
        #expect(!r.canRedeem)
        #expect(RewardsAvailability.nextRewardLine(r) == "75 more points for a free drip coffee · about 3 more visits")
    }

    @Test func enoughPointsSaysSoAndNamesTheBestAffordableReward() {
        let r = RewardsAvailability.nextReward(details(balance: 160))!
        #expect(r.title == "Free croissant with any latte")
        #expect(r.canRedeem)
        #expect(r.fraction == 1)
        #expect(RewardsAvailability.nextRewardLine(r) == "You've got enough for a free croissant with any latte. Scan at the register to use it.")
    }

    @Test func unknownEarnRateSkipsTheVisitCount() {
        let r = RewardsAvailability.nextReward(details(balance: 99, rate: nil))!
        #expect(r.visitsLeft == nil)
        #expect(RewardsAvailability.nextRewardLine(r) == "1 more point for a free drip coffee")
    }

    @Test func noOffersMeansNoCard() {
        #expect(RewardsAvailability.nextReward(details(balance: 10, offers: [])) == nil)
        #expect(RewardsAvailability.nextReward(details(balance: 10, offers: [("Broken", 0)])) == nil)
    }

    @Test func articlesReadNaturally() {
        let an = RewardsAvailability.nextReward(details(balance: 0, offers: [("Espresso shot", 50)]))!
        #expect(RewardsAvailability.nextRewardLine(an).contains("for an espresso shot"))
        let the = RewardsAvailability.nextReward(details(balance: 0, offers: [("The weekend special", 50)]))!
        #expect(RewardsAvailability.nextRewardLine(the).contains("for The weekend special"))
    }
}
