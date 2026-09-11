import Testing
import Foundation
@testable import Circles_iOS

/// The home map's people/category scoping. Places are attributed to their
/// circle's owner when the circle is known, else to whoever added them.
struct HomePlaceFilterTests {
    private let me = "me"

    private func place(_ id: String, circle: String?, addedBy: String, category: PlaceCategory = .restaurant, custom: String? = nil) -> Place {
        Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: category, customCategoryId: custom,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: circle, addedBy: addedBy, addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }
    private func circle(_ id: String, owner: String, showOnMap: Bool? = nil) -> Circle {
        Circle(id: id, name: id, description: nil, coverImage: nil, owner: owner, ownerDetails: nil,
               editors: nil, editorsDetails: nil, places: nil, placesCount: nil, placesWithDetails: nil,
               privacy: .public, allowNetworkEdit: nil, showOnMap: showOnMap, category: .other,
               location: nil, tags: nil, sharedWith: nil, followers: nil, activeShares: nil,
               shareSettings: nil, isSharedWithMe: nil, sharedBy: nil, myAccessLevel: nil,
               createdAt: Date(), updatedAt: Date())
    }
    private func ids(_ places: [Place]) -> [String] { places.map { $0.id } }

    /// Own circle "mine"; network circles "bobs" (owner bob), "carls" (owner carl).
    private var context: HomePlaceFilter.Context {
        var c = HomePlaceFilter.Context()
        c.currentUserId = me
        c.ownCircleIds = ["mine"]
        c.networkCircleOwners = ["bobs": "bob", "carls": "carl", "mine-shared": me]
        c.acceptedConnectionUserIds = ["bob"]
        c.everyoneAuthorIds = [me, "bob", "followed"]
        return c
    }
    private var sample: [Place] {
        [
            place("p-mine", circle: "mine", addedBy: me),
            place("p-bob", circle: "bobs", addedBy: "bob"),
            place("p-carl", circle: "carls", addedBy: "carl"),
            place("p-followed-viewport", circle: "unknownCircle", addedBy: "followed"),   // circle not loaded
            place("p-stranger", circle: nil, addedBy: "stranger", category: .cafe),
            place("p-mine-shared", circle: "mine-shared", addedBy: "someone-else")      // my circle via network list
        ]
    }

    @Test func everyoneScopeIsMeConnectionsAndFollowed() {
        let out = HomePlaceFilter.apply(sample, context: context)
        #expect(ids(out) == ["p-mine", "p-bob", "p-followed-viewport", "p-mine-shared"])
    }

    @Test func myPlacesOnlyIncludesCirclesIOwnEvenViaTheNetworkList() {
        var c = context; c.selectedConnectionId = HomePlaceFilter.myPlacesOnlyId
        #expect(ids(HomePlaceFilter.apply(sample, context: c)) == ["p-mine", "p-mine-shared"])
    }

    @Test func myPlacesOnlyWithNoCirclesLoadedIsEmpty() {
        var c = HomePlaceFilter.Context(); c.currentUserId = me
        c.selectedConnectionId = HomePlaceFilter.myPlacesOnlyId
        #expect(HomePlaceFilter.apply(sample, context: c).isEmpty)
    }

    @Test func myConnectionsOnlyIsTheNarrowerCut() {
        var c = context; c.selectedConnectionId = HomePlaceFilter.myConnectionsOnlyId
        #expect(ids(HomePlaceFilter.apply(sample, context: c)) == ["p-bob"])
    }

    @Test func onePersonMatchesByCircleOwnerOrAddedByFallback() {
        var c = context; c.selectedConnectionId = "carl"
        #expect(ids(HomePlaceFilter.apply(sample, context: c)) == ["p-carl"])

        c.selectedConnectionId = "followed"    // only reachable via addedBy (circle unknown)
        #expect(ids(HomePlaceFilter.apply(sample, context: c)) == ["p-followed-viewport"])

        c.selectedConnectionId = "someone-else" // addedBy is ignored once the circle owner is known
        #expect(HomePlaceFilter.apply(sample, context: c).isEmpty)
    }

    @Test func hiddenCirclesAreDroppedBeforeScoping() {
        var c = context; c.hiddenCircleIds = ["bobs"]
        #expect(ids(HomePlaceFilter.apply(sample, context: c)) == ["p-mine", "p-followed-viewport", "p-mine-shared"])
        #expect(HomePlaceFilter.hiddenCircleIds(in: [circle("a", owner: me, showOnMap: false), circle("b", owner: me), circle("c", owner: me, showOnMap: true)]) == ["a"])
    }

    @Test func categoryChipAppliesLast() {
        var c = context; c.selectedCategory = .standard(.cafe)
        c.everyoneAuthorIds.insert("stranger")
        #expect(ids(HomePlaceFilter.apply(sample, context: c)) == ["p-stranger"])
    }

    @Test func idsAreComparedThroughTheNormalizer() {
        // A provider-prefixed id and the bare id are the same person.
        var c = context; c.selectedConnectionId = "bob"
        let prefixed = [place("p-x", circle: nil, addedBy: "google.bob.1")]
        let bare = HomePlaceFilter.apply(prefixed, context: c)
        #expect(ids(bare) == (IDNormalizer.isSameUser("google.bob.1", "bob") ? ["p-x"] : []))
    }
}
