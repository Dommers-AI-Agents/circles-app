import Foundation
import Testing
@testable import Circles_iOS

/// A shared place is one bubble: a card with the key facts whose tap opens
/// the place in FavCircles (Wes, 2026-11-12: a shared farmers market opened
/// nothing and sent people to the market's website).
struct PlaceShareCopyTests {
    @Test func aSaveOrAVenueSharesItsOwnId() {
        #expect(PlaceShareCopy.target(id: "save1", globalPlaceId: "v1", googlePlaceId: "g1", addedBy: "wes") == .place(id: "save1"))
        #expect(PlaceShareCopy.target(id: "v1", globalPlaceId: "v1", googlePlaceId: "g1", addedBy: "") == .place(id: "v1"))
    }

    @Test func aGoogleOnlyPlaceIsMadeIntoAVenueFirst() {
        // The Locals tab's market page: its id is the Google id
        #expect(PlaceShareCopy.target(id: "g1", globalPlaceId: nil, googlePlaceId: "g1", addedBy: "") == .mint(googlePlaceId: "g1"))
        #expect(PlaceShareCopy.target(id: "local-market", globalPlaceId: nil, googlePlaceId: "g1", addedBy: "") == .mint(googlePlaceId: "g1"))
    }

    @Test func nothingToOpenFallsBackToTheAppStore() {
        #expect(PlaceShareCopy.target(id: "local-market", globalPlaceId: nil, googlePlaceId: nil, addedBy: "") == .appStore)
        #expect(PlaceShareCopy.target(id: "", globalPlaceId: "", googlePlaceId: "", addedBy: "") == .appStore)
    }

    @Test func aMarketShowsItsDaysAndWhere() throws {
        let json = #"""
        {"id":"308508","name":"San Tan Valley Farmers Market","address":"San Tan Valley AZ 85140, US","lat":33.2,"lng":-111.5,
         "acceptsSnap":true,"googlePlaceId":"g1","photoUrl":"https://x/p.jpg","hoursSummary":"Sat 8 AM–12 PM"}
        """#
        let market = try JSONDecoder().decode(FarmersMarket.self, from: Data(json.utf8))
        let card = PlaceShareCopy.content(for: market)
        #expect(card.title == "San Tan Valley Farmers Market")
        #expect(card.kicker == "Farmers market")
        #expect(card.when == "Sat 8 AM–12 PM")
        #expect(card.whereLine == "San Tan Valley AZ 85140, US")
        #expect(card.extra == "SNAP/EBT")
        #expect(card.photoUrl == "https://x/p.jpg")
        #expect(PlaceShareCopy.target(for: market) == .mint(googlePlaceId: "g1"))
    }

    @Test func anEventOpensItsVenueNotTheTicketSite() throws {
        let json = #"""
        {"id":"e1","source":"ticketmaster","name":"Jazz Night","startLocalDate":"2026-11-15","startLocalTime":"19:00:00",
         "venueName":"The Hall","city":"Mesa","url":"https://tickets.example/e1","isFree":true,"googlePlaceId":"g7"}
        """#
        let event = try JSONDecoder().decode(NearbyEvent.self, from: Data(json.utf8))
        let card = PlaceShareCopy.content(for: event)
        #expect(card.title == "Jazz Night")
        #expect(card.kicker == "Event")
        #expect(card.whereLine == "The Hall · Mesa")
        #expect(card.extra == "Free")
        #expect(card.when?.isEmpty == false)
        #expect(PlaceShareCopy.target(for: event) == .mint(googlePlaceId: "g7"))
    }

    @Test func subcategoriesReadAsWords() {
        #expect(PlaceShareCopy.kicker(subcategory: "farmers_market") == "Farmers market")
        #expect(PlaceShareCopy.kicker(subcategory: "  ") == nil)
        #expect(PlaceShareCopy.kicker(subcategory: nil) == nil)
    }
}

struct OpeningHoursWeekSummaryTests {
    private func hours(_ json: String) throws -> [OpeningHour] {
        try JSONDecoder().decode([OpeningHour].self, from: Data(json.utf8))
    }

    @Test func daysWithTheSameHoursGroup() throws {
        let week = try hours(#"""
        [{"day":2,"open":"15:00","close":"19:00"},{"day":4,"open":"15:00","close":"19:00"},{"day":6,"open":"08:00","close":"13:00"}]
        """#)
        #expect(OpeningHoursFormatter.weekSummary(week) == "Tue, Thu 3 PM–7 PM · Sat 8 AM–1 PM")
    }

    @Test func closedDaysAndNothingKnown() throws {
        #expect(OpeningHoursFormatter.weekSummary([]) == nil)
        let closed = try hours(#"[{"day":1,"isClosed":true},{"day":6,"open":"08:00","close":"12:00"}]"#)
        #expect(OpeningHoursFormatter.weekSummary(closed) == "Sat 8 AM–12 PM")
    }
}
