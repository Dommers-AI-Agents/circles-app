import Testing
import Foundation
@testable import Circles_iOS

/// A search result's second line says how far, who saved it and the street
/// (Wes, 2026-11-07: the full address was cut off anyway).
struct SearchRowSubtitleTests {

    @Test func savedPlacesSayWhoSavedThem() {
        #expect(SearchRowSubtitle.make(distance: "0.2 mi", source: .saved(.init(count: 5, includesYou: false)),
                                       address: "1700 Camden Rd, Charlotte, NC, 28203")
                == "0.2 mi · Saved by 5 · Camden Rd")
        #expect(SearchRowSubtitle.make(distance: "700 ft", source: .saved(.init(count: 3, includesYou: true)),
                                       address: "1440 S Tryon St, Charlotte")
                == "700 ft · Saved by you + 2 · S Tryon St")
        #expect(SearchRowSubtitle.make(distance: nil, source: .saved(.init(count: 1, includesYou: true)), address: "")
                == "Saved by you")
        #expect(SearchRowSubtitle.make(distance: nil, source: .saved(.init(count: 1, includesYou: false, firstName: "Dana")),
                                       address: "9 Oak Ave")
                == "Saved by Dana · Oak Ave")
    }

    @Test func nearbyPlacesSayWhereTheyComeFrom() {
        #expect(SearchRowSubtitle.make(distance: "0.6 mi", source: .favCircles, address: "1 Main St") == "0.6 mi · On FavCircles")
        #expect(SearchRowSubtitle.make(distance: "1.2 mi", source: .appleMaps, address: "1 Main St") == "1.2 mi · Apple Maps")
    }

    @Test func streetDropsTheHouseNumber() {
        #expect(SearchRowSubtitle.street(from: "1514, S Church St, Charlotte, NC") == "S Church St")
        #expect(SearchRowSubtitle.street(from: "Camden Rd, Charlotte") == "Camden Rd")
        #expect(SearchRowSubtitle.street(from: "12-14 Bank St") == "Bank St")
        #expect(SearchRowSubtitle.street(from: "") == nil)
    }
}
