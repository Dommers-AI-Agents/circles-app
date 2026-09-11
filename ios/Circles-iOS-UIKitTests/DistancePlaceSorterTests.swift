import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// Nearest-first ordering for the map lists, unlocated places last.
struct DistancePlaceSorterTests {
    private func place(_ name: String, lat: Double?, lon: Double?) -> Place {
        let location = (lat != nil && lon != nil) ? GeoLocation(type: "Point", coordinates: [lon!, lat!]) : nil
        return Place(id: name, name: name, description: nil, address: "", location: location, website: nil, phone: nil,
                     googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
                     subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
                     publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
                     likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "me", addedByUser: nil,
                     privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func nearestFirstThenUnlocatedAlphabetically() {
        let reference = CLLocation(latitude: 35.2271, longitude: -80.8431)
        let places = [
            place("zeta (no location)", lat: nil, lon: nil),
            place("far", lat: 35.7796, lon: -78.6382),
            place("alpha (no location)", lat: nil, lon: nil),
            place("near", lat: 35.2280, lon: -80.8431)
        ]
        let sorted = DistancePlaceSorter.sorted(places, from: reference)
        #expect(sorted.map { $0.place.id } == ["near", "far", "alpha (no location)", "zeta (no location)"])
        #expect(sorted[0].distance! < sorted[1].distance!)
        #expect(sorted[2].distance == nil)
    }
}
