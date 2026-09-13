import Testing
import MapKit
@testable import Circles_iOS

/// Filling the add-place form from an Apple Maps result.
struct AppleMapItemFormFillTests {
    typealias M = AppleMapItemFormFill.CategoryMapping

    @Test func residentialMeansNoName() {
        #expect(AppleMapItemFormFill.isResidentialAddress(name: nil))
        #expect(AppleMapItemFormFill.isResidentialAddress(name: ""))
        #expect(!AppleMapItemFormFill.isResidentialAddress(name: "Joe's"))
    }

    @Test func poiCategoriesMapWithSubcategories() {
        let f = AppleMapItemFormFill.categoryMapping
        #expect(f(.restaurant, nil) == M(.restaurant))
        #expect(f(.cafe, nil) == M(.cafe, "Coffee Shop"))
        #expect(f(.brewery, nil) == M(.bar, "Brewery"))
        #expect(f(.campground, nil) == M(.hotel))
        #expect(f(.foodMarket, nil) == M(.retail, "Grocery Store"))
        #expect(f(.evCharger, nil) == M(.service))
        #expect(f(.atm, nil) == M(.finance))
        #expect(f(.hospital, nil) == M(.healthcare, "Hospital"))
        #expect(f(.parking, nil) == M(.transport, "Parking"))
        #expect(f(.library, nil) == M(.education))
        #expect(f(.park, nil) == M(.outdoor, "Park"))
        #expect(f(.beach, nil) == M(.outdoor, "Beach"))
        #expect(f(.nationalPark, nil) == M(.outdoor))
        #expect(f(.zoo, nil) == M(.attraction, "Zoo"))
        #expect(f(.aquarium, nil) == M(.attraction, "Aquarium"))
        #expect(f(.amusementPark, nil) == M(.attraction, "Theme Park"))
        #expect(f(.stadium, nil) == M(.entertainment))
        // A POI category wins over any name hint
        #expect(f(.marina, "Harbor Grill") == M(.outdoor))
        #expect(f(MKPointOfInterestCategory(rawValue: "MKPOICategoryUnknownThing"), "Joe's Grill") == M(.other))
    }

    @Test func nameInferenceWhenAppleGivesNoCategory() {
        let f = AppleMapItemFormFill.categoryMapping
        #expect(f(nil, "Joe's Kitchen") == M(.restaurant))
        #expect(f(nil, "Daily Coffee") == M(.cafe))
        #expect(f(nil, "The Crown Pub") == M(.bar))
        #expect(f(nil, "Seaside Inn") == M(.hotel))
        #expect(f(nil, "Corner Market") == M(.retail))
        #expect(f(nil, "Something Else") == M(.other))
        #expect(f(nil, nil) == M(.other))
    }

    @Test func descriptionComposesCategoryCityPhoneWebsite() {
        #expect(AppleMapItemFormFill.description(poiCategory: .cafe, locality: "Phoenix", phone: "555", website: URL(string: "https://x.test"))
                == "A coffee shop or casual dining spot in Phoenix\nPhone: 555\nWebsite: https://x.test")
        #expect(AppleMapItemFormFill.description(poiCategory: nil, locality: "Phoenix", phone: nil, website: nil) == "Located in Phoenix")
        #expect(AppleMapItemFormFill.description(poiCategory: .restaurant, locality: nil, phone: nil, website: nil) == "A dining establishment")
        #expect(AppleMapItemFormFill.description(poiCategory: nil, locality: nil, phone: "1", website: nil) == "\nPhone: 1")
    }
}
