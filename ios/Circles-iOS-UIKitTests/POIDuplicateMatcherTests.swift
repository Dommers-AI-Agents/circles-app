import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// A tapped map point of interest counts as already saved when a place with
/// a matching name sits within about a hundred meters.
struct POIDuplicateMatcherTests {
    private func place(_ name: String, lat: Double?, lon: Double?) -> Place {
        let location = (lat != nil && lon != nil) ? GeoLocation(type: "Point", coordinates: [lon!, lat!]) : nil
        return Place(id: name, name: name, description: nil, address: "", location: location, website: nil, phone: nil,
                     googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
                     subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
                     publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
                     likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "me", addedByUser: nil,
                     privacy: .public, createdAt: Date(), updatedAt: Date())
    }
    private let here = CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)
    /// ~0.0009° of latitude is about 100 m
    private var nearby: (Double, Double) { (35.2271 + 0.0005, -80.8431) }
    private var farther: (Double, Double) { (35.2271 + 0.002, -80.8431) }

    @Test func namesMatchEitherWay() {
        #expect(POIDuplicateMatcher.namesMatch("Amelie's", "amelie's"))
        #expect(POIDuplicateMatcher.namesMatch("Amelie's French Bakery", "Amelie's"))
        #expect(POIDuplicateMatcher.namesMatch("Amelie's", "Amelie's French Bakery"))
        #expect(!POIDuplicateMatcher.namesMatch("Amelie's", "Bojangles"))
    }

    @Test func matchNeedsBothNameAndProximity() {
        let places = [
            place("Bojangles", lat: nearby.0, lon: nearby.1),
            place("Amelie's", lat: farther.0, lon: farther.1),
            place("Amelie's French Bakery", lat: nearby.0, lon: nearby.1)
        ]
        let match = POIDuplicateMatcher.existingPlace(named: "Amelie's", at: here, in: places)
        #expect(match?.id == "Amelie's French Bakery")
        #expect(POIDuplicateMatcher.existingPlace(named: "Starbucks", at: here, in: places) == nil)
    }

    @Test func unlocatedPlacesNeverMatch() {
        let places = [place("Amelie's", lat: nil, lon: nil)]
        #expect(POIDuplicateMatcher.existingPlace(named: "Amelie's", at: here, in: places) == nil)
    }

    // MARK: - Search hits

    private func located(_ name: String, _ lat: Double, _ lng: Double) -> Place {
        Place(id: name, name: name, description: nil, address: "", location: GeoLocation(type: "Point", coordinates: [lng, lat]), website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil, subcategory: nil, rating: nil, userRatingsTotal: nil,
              notes: nil, privateNotes: nil, publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil, likesCount: nil, commentsCount: nil,
              circleId: "c", addedBy: "me", addedByUser: nil, privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func aSearchHitIsTheSameNameOrCloseWithASharedWord() {
        let saved = located("Pasta & Provisions", 35.2175, -80.8640)
        // 40 m away with a telling word in common: the same place.
        #expect(POIDuplicateMatcher.isSearchHit(name: "Pasta and Provisions Deli", coordinate: CLLocationCoordinate2D(latitude: 35.21785, longitude: -80.8640), place: saved))
        // 40 m away with nothing in common: a neighbour, not it. (Downtown,
        // proximity alone made "Pizz" claim every save near a pizzeria.)
        #expect(!POIDuplicateMatcher.isSearchHit(name: "P&P Deli", coordinate: CLLocationCoordinate2D(latitude: 35.21785, longitude: -80.8640), place: saved))
        #expect(!POIDuplicateMatcher.isSearchHit(name: "CIBO", coordinate: CLLocationCoordinate2D(latitude: 35.21785, longitude: -80.8640), place: saved))
        // 3 km away, the same name spelled differently: the same place.
        #expect(POIDuplicateMatcher.isSearchHit(name: "The Pasta and Provisions", coordinate: CLLocationCoordinate2D(latitude: 35.24, longitude: -80.86), place: saved))
        // Neither: not it.
        #expect(!POIDuplicateMatcher.isSearchHit(name: "Mint Street Deli", coordinate: CLLocationCoordinate2D(latitude: 35.24, longitude: -80.86), place: saved))
        #expect(POIDuplicateMatcher.normalizedName("The Pasta & Provisions!") == "pasta and provisions")
    }

    @Test func partitionClaimsEachSavedPlaceOnce() {
        let saved = [located("Pasta & Provisions", 35.2175, -80.8640)]
        let split = POIDuplicateMatcher.partition(candidates: [located("Pasta and Provisions", 35.2175, -80.8640), located("Pasta & Provisions Deli", 35.2176, -80.8641), located("Other Deli", 35.30, -80.90)], saved: saved)
        #expect(split.matched.map(\.id) == ["Pasta & Provisions"])
        #expect(split.unsaved.map(\.name) == ["Pasta & Provisions Deli", "Other Deli"])
    }
}

/// The keyed fast path must answer exactly like the per-pair one.
struct POIDuplicateMatcherKeyTests {
    @Test func aKeyIsTheNormalisedNameAndItsTellingWords() {
        let key = POIDuplicateMatcher.NameKey("The Pasta & Provisions Café")
        #expect(key.normalized == POIDuplicateMatcher.normalizedName("The Pasta & Provisions Café"))
        #expect(key.words == POIDuplicateMatcher.significantWords("The Pasta & Provisions Café"))
        #expect(key.words == ["pasta", "provisions"])
    }
}
