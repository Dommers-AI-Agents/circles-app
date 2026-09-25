import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// Which saved places get a location-triggered check-in banner: the nearest
/// venues to the user, under iOS's 20-region cap.
struct ProximityRegionPlannerTests {
    private let origin = CLLocation(latitude: 40.7484, longitude: -73.9857) // Empire State

    /// A place `meters` due north of the origin. 1° latitude ≈ 111,320 m.
    private func place(_ id: String, meters: Double, name: String? = nil, located: Bool = true) -> Place {
        let location = located
            ? GeoLocation(type: "Point", coordinates: [origin.coordinate.longitude,
                                                       origin.coordinate.latitude + meters / 111_320])
            : nil
        return Place(id: id, name: name ?? id, description: nil, address: "", location: location, website: nil,
                     phone: nil, googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant,
                     customCategoryId: nil, subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil,
                     privateNotes: nil, publicNotes: nil, tags: nil, reviews: nil, openingHours: nil,
                     priceLevel: nil, likes: nil, likesCount: nil, commentsCount: nil, circleId: "c",
                     addedBy: "u", addedByUser: nil, privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func nearestFirstAndCappedAtTheRegionLimit() {
        // 30 places, 100 m apart starting past the trigger radius, shuffled
        // so order in != order out
        let places = (1...30).map { place("p\($0)", meters: 150 + Double($0) * 100) }.shuffled()
        let plan = ProximityRegionPlanner.plan(places: places, around: origin)

        #expect(plan.count == ProximityRegionPlanner.regionLimit)
        #expect(plan.map { $0.placeId } == (1...20).map { "p\($0)" })
        #expect(plan.allSatisfy { $0.radius == ProximityRegionPlanner.defaultRadiusMeters })
        #expect(plan.first?.identifier == "proximity.p1")
    }

    @Test func placesTheUserIsAlreadyInsideAreNotScheduled() {
        let radius = ProximityRegionPlanner.defaultRadiusMeters
        let places = [
            place("here", meters: 10),
            place("edge", meters: radius),
            place("justOutside", meters: radius + 1),
            place("far", meters: 500)
        ]
        let plan = ProximityRegionPlanner.plan(places: places, around: origin)
        #expect(plan.map { $0.placeId } == ["justOutside", "far"])
    }

    @Test func excludedAndUnlocatedAndUnnamedPlacesAreSkipped() {
        let places = [
            place("today", meters: 200),
            place("nowhere", meters: 210, located: false),
            place("blank", meters: 220, name: "   "),
            place("ok", meters: 230)
        ]
        let plan = ProximityRegionPlanner.plan(places: places, around: origin, excludedPlaceIds: ["today"])
        #expect(plan.map { $0.placeId } == ["ok"])
    }

    @Test func coincidentSavesCollapseToOneRegionKeepingTheNearest() {
        let places = [
            place("copyInSecondCircle", meters: 320),
            place("original", meters: 300),
            place("acrossTheStreet", meters: 300 + ProximityRegionPlanner.sameVenueMeters + 5)
        ]
        let plan = ProximityRegionPlanner.plan(places: places, around: origin)
        #expect(plan.map { $0.placeId } == ["original", "acrossTheStreet"])
    }

    @Test func noLocationMeansNoPlan() {
        #expect(ProximityRegionPlanner.plan(places: [place("a", meters: 10)], around: nil).isEmpty)
        #expect(ProximityRegionPlanner.plan(places: [place("a", meters: 10)], around: origin, limit: 0).isEmpty)
    }

    @Test func identifiersRoundTripToPlaceIds() {
        #expect(ProximityRegionPlanner.placeId(fromIdentifier: "proximity.abc") == "abc")
        #expect(ProximityRegionPlanner.placeId(fromIdentifier: "proximity.") == nil)
        #expect(ProximityRegionPlanner.placeId(fromIdentifier: "test") == nil)
    }

    /// A place under an arrival watch must keep its region whatever the plan
    /// says: it is inside the radius, it has been stamped for the day, and
    /// twenty-five nearer places would otherwise push it past the cap.
    @Test func pinnedPlaceSurvivesInsideExcludedAndTheCap() {
        var places = (1...25).map { place("near\($0)", meters: Double(200 + 40 * $0)) }  // spaced past sameVenueMeters
        places.append(place("watched", meters: 10))
        let plan = ProximityRegionPlanner.plan(places: places, around: origin,
                                               excludedPlaceIds: ["watched"], pinnedPlaceIds: ["watched"])
        #expect(plan.count == ProximityRegionPlanner.regionLimit)
        #expect(plan.first?.placeId == "watched")
        let unpinned = ProximityRegionPlanner.plan(places: places, around: origin, excludedPlaceIds: ["watched"])
        #expect(!unpinned.contains { $0.placeId == "watched" })
    }
}
