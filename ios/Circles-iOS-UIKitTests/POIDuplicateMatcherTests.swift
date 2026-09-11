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
}
