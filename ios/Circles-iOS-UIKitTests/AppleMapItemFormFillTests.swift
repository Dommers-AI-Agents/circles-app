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
        #expect(f(.fitnessCenter, nil) == M(.fitness, "Gym"))
        #expect(f(.bakery, nil) == M(.cafe, "Bakery"))
        #expect(f(.airport, nil) == M(.transport, "Airport"))
        // A mapped POI category wins over any name hint
        #expect(f(.marina, "Harbor Grill") == M(.outdoor))
        // An unmapped one falls through to the name instead of "Other"
        #expect(f(MKPointOfInterestCategory(rawValue: "MKPOICategoryUnknownThing"), "Joe's Grill") == M(.restaurant))
        #expect(f(MKPointOfInterestCategory(rawValue: "MKPOICategoryUnknownThing"), "Acme Widgets") == M(.other))
    }

    /// Apple has no clinic/dentist/gym-studio categories, so these arrive
    /// with no POI category and the name has to carry them — the map pin icon
    /// depends on it.
    @Test func healthcareAndOtherBusinessesAreRecognizedByName() {
        let f = AppleMapItemFormFill.categoryMapping
        #expect(f(nil, "Atrium Health Urgent Care") == M(.healthcare))
        #expect(f(nil, "Novant Health Pediatrics") == M(.healthcare))
        #expect(f(nil, "SouthPark Family Dental") == M(.healthcare))
        #expect(f(nil, "CVS Pharmacy") == M(.healthcare))
        #expect(f(nil, "Charlotte Animal Hospital") == M(.healthcare))
        #expect(f(nil, "Orangetheory Fitness") == M(.fitness))
        #expect(f(nil, "CorePower Yoga") == M(.fitness))
        #expect(f(nil, "Sycamore Brewing") == M(.bar))
        #expect(f(nil, "Amélie's French Bakery") == M(.cafe))
        #expect(f(nil, "Sal's Pizzeria") == M(.restaurant))
        #expect(f(nil, "Great Clips Salon") == M(.service))
        #expect(f(nil, "Freedom Park") == M(.outdoor))
        #expect(f(nil, "Mint Museum") == M(.attraction))
    }

    /// Whole words only, and specific rules before generic ones.
    @Test func nameRulesDoNotMisfireOnSubstrings() {
        let f = AppleMapItemFormFill.categoryMapping
        #expect(f(nil, "Barnes & Noble") == M(.other))       // not a bar
        #expect(f(nil, "Finnegan's Wake") == M(.other))    // not an inn
        #expect(f(nil, "Public Storage") == M(.other))       // not a pub
        #expect(f(nil, "Tom's Barbershop") == M(.service)) // barber, not bar
        #expect(f(nil, "Urgent Care Pharmacy") == M(.healthcare))
        #expect(f(nil, "Pub Burger") == M(.bar))             // first rule wins
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
