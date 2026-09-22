import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// The nearby section: catalog and Apple venues, minus what's already yours.
struct SuggestedNearbyMergerTests {
    private func place(_ name: String, _ lat: Double, _ lng: Double, saved: Bool = false) -> Place {
        Place(id: name, name: name, description: nil, address: "", location: GeoLocation(type: "Point", coordinates: [lng, lat]), website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil, subcategory: nil, rating: nil, userRatingsTotal: nil,
              notes: nil, privateNotes: nil, publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil, likesCount: nil, commentsCount: nil,
              circleId: saved ? "c" : "", addedBy: "me", addedByUser: nil, privacy: .public, createdAt: Date(), updatedAt: Date())
    }
    private let me = CLLocation(latitude: 35.2200, longitude: -80.8500)

    @Test func savedPlacesAreNotSuggestionsAndTheRestAreNearestFirst() {
        let saved = [place("Pasta & Provisions", 35.2175, -80.8640, saved: true)]
        let apple = [place("Pasta and Provisions", 35.2175, -80.8640), place("Far Deli", 35.40, -80.70), place("Near Deli", 35.2210, -80.8510)]
        let rows = SuggestedNearbyMerger.merge(global: [], apple: apple, saved: saved, from: me)
        #expect(rows.map { $0.row.id } == ["Near Deli", "Far Deli"])
        #expect(rows[0].distance! < rows[1].distance!)
    }

    @Test func capIsEightAndEmptyInputsAreEmpty() {
        let apple = (0..<12).map { place("Deli \($0)", 35.22 + Double($0) * 0.001, -80.85) }
        #expect(SuggestedNearbyMerger.merge(global: [], apple: apple, saved: [], from: me).count == 8)
        #expect(SuggestedNearbyMerger.merge(global: [], apple: [], saved: [], from: nil).isEmpty)
    }
}
