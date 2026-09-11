import Testing
import Foundation
@testable import Circles_iOS

/// The full-screen map's people scope: pre-bucketed connection lists plus
/// an addedBy sweep, so places saved under a connection's legacy id and
/// viewport-fetched places that were never bucketed both survive.
struct MapPlaceScopeTests {
    private let me = "me"

    private func place(_ id: String, addedBy: String) -> Place {
        Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: nil, addedBy: addedBy, addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }
    private func ids(_ places: [Place]) -> Set<String> { Set(places.map { $0.id }) }

    /// bob is an accepted connection, fay is only followed, zed is a stranger.
    /// bob's bucket carries "bob-bucketed" (saved under bob's legacy id, so
    /// its addedBy doesn't match him); "bob-viewport" was never bucketed.
    private var context: MapPlaceScope.Context {
        var c = MapPlaceScope.Context()
        c.currentUserId = me
        c.acceptedConnectionUserIds = ["bob"]
        c.followingUserIds = ["fay"]
        c.bucketedPlaces = ["bob": [place("bob-bucketed", addedBy: "bob-legacy")]]
        return c
    }
    private var current: [Place] {
        [
            place("mine", addedBy: me),
            place("bob-viewport", addedBy: "bob"),
            place("fay-place", addedBy: "fay"),
            place("zed-place", addedBy: "zed")
        ]
    }

    @Test func everyoneIsMePlusConnectionsPlusFollowed() {
        let result = MapPlaceScope.apply(current, context: context)
        #expect(ids(result) == ["mine", "bob-bucketed", "bob-viewport", "fay-place"])
    }

    @Test func myPlacesOnlyMatchesAddedBy() {
        var c = context
        c.selectedConnectionId = HomePlaceFilter.myPlacesOnlyId
        #expect(ids(MapPlaceScope.apply(current, context: c)) == ["mine"])
    }

    @Test func myConnectionsExcludesMeAndFollowed() {
        var c = context
        c.selectedConnectionId = HomePlaceFilter.myConnectionsOnlyId
        #expect(ids(MapPlaceScope.apply(current, context: c)) == ["bob-bucketed", "bob-viewport"])
    }

    @Test func onePersonUnionsBucketAndSweepWithoutDuplicates() {
        var c = context
        c.selectedConnectionId = "bob"
        c.bucketedPlaces = ["bob": [place("bob-bucketed", addedBy: "bob-legacy"), place("bob-viewport", addedBy: "bob")]]
        let result = MapPlaceScope.apply(current, context: c)
        #expect(result.map { $0.id } == ["bob-bucketed", "bob-viewport"])
    }

    @Test func unknownPersonNeverFallsThroughToEveryone() {
        var c = context
        c.selectedConnectionId = "nobody"
        #expect(MapPlaceScope.apply(current, context: c).isEmpty)
    }
}
