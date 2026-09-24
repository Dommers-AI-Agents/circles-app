import Foundation
import MapKit
import Testing
@testable import Circles_iOS

/// Only the places in and around the screen get annotation views.
struct MapViewportCullerTests {
    private func place(_ id: String, lat: Double?, lng: Double?) -> Place {
        let location = (lat != nil && lng != nil) ? GeoLocation(type: "Point", coordinates: [lng!, lat!]) : nil
        return Place(id: id, name: id, description: nil, address: "", location: location, website: nil, phone: nil,
                     googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
                     subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
                     publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
                     likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "me", addedByUser: nil,
                     privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    /// A rect around Charlotte about 0.02° tall (≈2 km).
    private var charlotte: MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: 35.23, longitude: -80.85))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: 35.21, longitude: -80.83))
        return MKMapRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    @Test func keepsWhatIsOnScreenAndJustOffIt() {
        let places = [
            place("centre", lat: 35.22, lng: -80.84),
            place("edge", lat: 35.2295, lng: -80.84),      // inside the padded margin
            place("newJersey", lat: 40.17, lng: -74.05),
            place("noLocation", lat: nil, lng: nil)
        ]
        let shown = MapViewportCuller.placesToShow(places, visibleRect: charlotte)
        #expect(shown.map(\.id) == ["centre", "edge"])
    }

    @Test func capsAtTheNearestToCentre() {
        var places: [Place] = []
        for i in 0..<50 {
            places.append(place("p\(i)", lat: 35.22 + Double(i) * 0.0002, lng: -80.84))
        }
        let shown = MapViewportCuller.placesToShow(places, visibleRect: charlotte, cap: 5)
        #expect(shown.count == 5)
        #expect(shown.map(\.id).contains("p0"))
        #expect(!shown.map(\.id).contains("p49"))
    }

    @Test func aMapNotLaidOutYetShowsEverything() {
        let places = [place("a", lat: 35.22, lng: -80.84), place("b", lat: 40.17, lng: -74.05)]
        #expect(MapViewportCuller.placesToShow(places, visibleRect: .null).count == 2)
    }

    @Test func aSmallPanStaysInsideThePadding() {
        let before = charlotte
        let nudged = before.offsetBy(dx: before.size.width * 0.1, dy: 0)
        #expect(!MapViewportCuller.needsRecull(previousVisibleRect: before, currentVisibleRect: nudged))
        let far = before.offsetBy(dx: before.size.width * 0.6, dy: 0)
        #expect(MapViewportCuller.needsRecull(previousVisibleRect: before, currentVisibleRect: far))
    }

    @Test func aZoomOfAQuarterRecullsAndTheFirstPassAlwaysDoes() {
        let before = charlotte
        let zoomedOut = before.insetBy(dx: -before.size.width * 0.5, dy: -before.size.height * 0.5)
        #expect(MapViewportCuller.needsRecull(previousVisibleRect: before, currentVisibleRect: zoomedOut))
        #expect(MapViewportCuller.needsRecull(previousVisibleRect: nil, currentVisibleRect: before))
    }
}
