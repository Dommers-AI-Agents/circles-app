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
}
