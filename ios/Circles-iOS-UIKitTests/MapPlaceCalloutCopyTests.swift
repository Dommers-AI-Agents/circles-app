import Foundation
import Testing
@testable import Circles_iOS

/// The card on a tapped map place (Wes, 2026-11-12): what it is and how far.
struct MapPlaceCalloutCopyTests {
    @Test func appleCategoriesReadAsWords() {
        #expect(MapPlaceCalloutCopy.categoryName(rawValue: "MKPOICategoryRestaurant") == "Restaurant")
        #expect(MapPlaceCalloutCopy.categoryName(rawValue: "MKPOICategoryNationalPark") == "National park")
        #expect(MapPlaceCalloutCopy.categoryName(rawValue: "MKPOICategoryEVCharger") == "EV charger")
        #expect(MapPlaceCalloutCopy.categoryName(rawValue: "MKPOICategoryATM") == "ATM")
        #expect(MapPlaceCalloutCopy.categoryName(rawValue: nil) == nil)
        #expect(MapPlaceCalloutCopy.categoryName(rawValue: "MKPOICategory") == nil)
    }

    @Test func distancesInFeetThenMiles() {
        #expect(MapPlaceCalloutCopy.distance(meters: nil) == nil)
        #expect(MapPlaceCalloutCopy.distance(meters: 76) == "250 ft")
        #expect(MapPlaceCalloutCopy.distance(meters: 1) == "10 ft")
        #expect(MapPlaceCalloutCopy.distance(meters: 644) == "0.4 mi")
        #expect(MapPlaceCalloutCopy.distance(meters: 20_000) == "12 mi")
    }

    @Test func theLineUnderTheName() {
        #expect(MapPlaceCalloutCopy.detail(category: "MKPOICategoryRestaurant", meters: 644) == "Restaurant · 0.4 mi")
        #expect(MapPlaceCalloutCopy.detail(category: nil, meters: 644) == "0.4 mi")
        #expect(MapPlaceCalloutCopy.detail(category: nil, meters: nil) == nil)
    }
}
