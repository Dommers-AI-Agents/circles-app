import Testing
import Foundation
@testable import Circles_iOS

/// What a search query is matched against, and where typos are forgiven.
struct PlaceSearchTextTests {
    private func place(_ name: String, address: String = "", category: PlaceCategory = .restaurant,
                       subcategory: String? = nil, custom: String? = nil, tags: [String]? = nil,
                       description: String? = nil) -> Place {
        Place(id: name, name: name, description: description, address: address, location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: category, customCategoryId: custom,
              subcategory: subcategory, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: tags, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "me", addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func descriptionMatchesOnlyAtWordStarts() {
        // Wes 2026-11-09: "Ups" listed YUME Ramen (description "upscale")
        // above The UPS Store.
        #expect(!place("YUME Ramen Sushi & Bar", description: "Upscale ramen and sushi").matches(searchQuery: "ups"))
        #expect(!place("Soup Spot", description: "Hearty soups and cups of tea").matches(searchQuery: "ups"))
        #expect(place("The UPS Store", category: .service).matches(searchQuery: "ups"))
        #expect(place("Somewhere", description: "Drop off your UPS returns").matches(searchQuery: "ups"))
        // Names still match inside a word.
        #expect(place("Cheeseburger Paradise").matches(searchQuery: "burger"))
        // Addresses still match where a word starts.
        #expect(place("Somewhere", address: "1800 Camden Rd").matches(searchQuery: "camd"))
        #expect(PlaceSearchText.containsWord("the ups store", "ups", wholeWord: true))
        #expect(!PlaceSearchText.containsWord("upscale soups", "ups", wholeWord: true))
        #expect(PlaceSearchText.containsWord("upscale soups", "ups"))
    }

    @Test func deliDoesNotFuzzMatchAStreetName() {
        // "deli" is one edit from "dela" — but the address is never fuzzed.
        #expect(!place("Nail Studio", address: "12 Delaware Ave, Belmar, NJ").matches(searchQuery: "deli"))
        #expect(place("Mint Street Delicatessen").matches(searchQuery: "deli"))
        // Exact address text still matches.
        #expect(place("Nail Studio", address: "12 Delaware Ave").matches(searchQuery: "delaware"))
    }

    @Test func categoryWordsAreSearchable() {
        #expect(place("Not Just Coffee", category: .cafe).matches(searchQuery: "coffee"))
        #expect(place("Pasta & Provisions", category: .restaurant).matches(searchQuery: "food"))
        #expect(place("Amelie's", category: .cafe, subcategory: "Bakery").matches(searchQuery: "bakery"))
        #expect(place("Petit Philippe", category: .other, custom: "Wine Shops").matches(searchQuery: "wine shops"))
    }

    @Test func tagsMatchButImportStampsDoNot() {
        #expect(place("Somewhere", tags: ["want-to-go"]).matches(searchQuery: "want to go"))
        #expect(!place("Somewhere", tags: ["google-import"]).matches(searchQuery: "google"))
    }

    @Test func typoToleranceIsForNamesOnly() {
        #expect(place("Pizza Hut").matches(searchQuery: "piza"))
        #expect(!place("Somewhere", description: "great pizza here").matches(searchQuery: "piza"))
        #expect(place("Somewhere", description: "great pizza here").matches(searchQuery: "pizza"))
    }

    /// The catalog's 3-letter retry ("Carbon" → "car") keeps only near misses
    /// (Wes, 2026-11-07: it listed a vet and an urgent care)
    @Test func catalogRetryKeepsOnlyNearMisses() {
        #expect(!Place.name("Carolina Veterinary Specialists Charlotte", matches: "Carbon"))
        #expect(!Place.name("NextCare Urgent Care", matches: "Carbon"))
        #expect(Place.name("Carbon Health", matches: "Carbon"))
        #expect(Place.name("Pizzeria Uno", matches: "piza"))
    }
}
