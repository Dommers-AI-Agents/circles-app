import Foundation
import MapKit
import Testing
@testable import Circles_iOS

/// Add from photos offers places, not addresses or homes (Wes, 2026-10-17).
struct PhotoPlaceKindTests {
    private func ok(_ name: String?, _ category: MKPointOfInterestCategory?, bare: Bool = false) -> Bool {
        PhotoPlaceKind.isPlace(name: name, categoryRaw: category?.rawValue, isBareAddress: bare)
    }

    @Test func rawValuesMatchMapKit() {
        for category in [MKPointOfInterestCategory.restaurant, .cafe, .hotel, .gasStation, .evCharger, .park, .airport, .school, .hospital] {
            #expect(PhotoPlaceKind.allowed.contains(category.rawValue), "\(category.rawValue)")
        }
        for category in [MKPointOfInterestCategory.atm, .parking, .police, .restroom] {
            #expect(PhotoPlaceKind.denied.contains(category.rawValue), "\(category.rawValue)")
        }
    }

    @Test func businessesAndVenuesCount() {
        #expect(ok("Optimist Hall", .foodMarket))
        #expect(ok("Amélie's French Bakery", .bakery))
        #expect(ok("Shell", .gasStation))
        #expect(ok("Freedom Park", .park))
        #expect(ok("Charlotte Douglas International Airport", .airport))
        #expect(ok("Mount Olivet Methodist Church", nil))   // no Apple category, the name says it
        #expect(ok("Sal's Pizza", nil))
    }

    @Test func homesAddressesAndServicesDont() {
        #expect(!ok("Waterford At The Park", .park))        // an apartment complex filed as a park
        #expect(!ok("The Ashton Apartments", nil))
        #expect(!ok("Matthews Reid House", nil))             // a house, no name signal
        #expect(!ok("300 East Blvd", nil, bare: true))
        #expect(!ok("Bank of America ATM", .atm))
        #expect(!ok("7th Street Parking Deck", .parking))
        #expect(!ok("Wells Fargo", nil))
        #expect(!ok("", .restaurant))
        #expect(!ok(nil, .restaurant))
        #expect(ok("The Lofts Hotel", .hotel))               // a real hotel keeps its name
    }

    @Test func theVenueBeatsTheShopNextDoor() {
        let store = MKPointOfInterestCategory.store.rawValue
        let foodHall = MKPointOfInterestCategory.foodMarket.rawValue
        let park = MKPointOfInterestCategory.park.rawValue
        let beauty = "MKPOICategoryBeauty"
        // A food hall 90 m away beats a shop 30 m away; a park 160 m away is in reach
        #expect(PhotoPlaceKind.rankScore(distance: 90, categoryRaw: foodHall) < PhotoPlaceKind.rankScore(distance: 30, categoryRaw: store))
        #expect(PhotoPlaceKind.reach(categoryRaw: park) > 160)
        #expect(PhotoPlaceKind.reach(categoryRaw: store) == 100)
        #expect(PhotoPlaceKind.rankScore(distance: 40, categoryRaw: MKPointOfInterestCategory.cafe.rawValue)
                < PhotoPlaceKind.rankScore(distance: 20, categoryRaw: beauty))
    }
}
