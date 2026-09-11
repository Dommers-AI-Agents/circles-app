import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// The home screen's data/selection state and the pure derivations the
/// controller reads from it (cache window, dedupe, filter context, category
/// chips, per-connection buckets, viewport coverage).
struct HomeStateTests {
    private let me = "me"

    private func place(_ id: String, circle: String?, addedBy: String, category: PlaceCategory = .restaurant) -> Place {
        Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: category, customCategoryId: nil,
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

    /// Own circle "mine"; network circles "bobs" (bob), "carls" (carl), and
    /// "mine-shared" (mine, arrived via the network list).
    private func loadedState() -> HomeState {
        let state = HomeState()
        state.circles = [circle("mine", owner: me)]
        state.networkCircles = [circle("bobs", owner: "bob"), circle("carls", owner: "carl"), circle("mine-shared", owner: me)]
        state.allPlaces = [
            place("p-mine", circle: "mine", addedBy: me),
            place("p-bob", circle: "bobs", addedBy: "bob-legacy-id"),
            place("p-carl", circle: "carls", addedBy: "carl"),
            place("p-orphan", circle: "not-loaded", addedBy: "bob"),
            place("p-mine-shared", circle: "mine-shared", addedBy: "someone-else")
        ]
        return state
    }

    // MARK: Cache

    @Test func cacheIsValidOnlyInsideTheWindowAndWhenNonEmpty() {
        let state = HomeState()
        #expect(!state.isCacheValid)

        state.cache([place("a", circle: nil, addedBy: me)])
        #expect(state.isCacheValid)

        state.cache([place("a", circle: nil, addedBy: me)], now: Date().addingTimeInterval(-10 * 60))
        #expect(!state.isCacheValid, "expired after cacheExpiryMinutes")

        state.cache([])
        #expect(!state.isCacheValid, "an empty cache is never valid")
    }

    @Test func invalidateClearsCacheAndOwnPlacesAndNotifies() {
        let state = HomeState()
        var notified: [[Place]] = []
        state.onUserOwnPlacesChanged = { notified.append($0) }
        state.userOwnPlaces = [place("a", circle: nil, addedBy: me)]
        state.cache(state.userOwnPlaces)

        state.invalidateCache()

        #expect(state.cachedPlaces.isEmpty)
        #expect(state.userOwnPlaces.isEmpty)
        #expect(state.placesCacheExpiry == nil)
        #expect(notified.map { $0.count } == [1, 0], "the map is told on every own-places write, including the clear")
    }

    // MARK: Dedupe

    @Test func dedupeKeepsFirstOccurrenceInOrder() {
        let out = HomeState.dedupe([place("a", circle: "1", addedBy: me), place("b", circle: nil, addedBy: me), place("a", circle: "2", addedBy: "x")])
        #expect(ids(out) == ["a", "b"])
        #expect(out[0].circleId == "1")
    }

    @Test func mergePrefersOwnCopyOverNetworkCopy() {
        let own = [place("a", circle: "mine", addedBy: me)]
        let network = [place("a", circle: "bobs", addedBy: "bob"), place("c", circle: "bobs", addedBy: "bob")]
        let out = HomeState.merge(userPlaces: own, networkPlaces: network)
        #expect(ids(out) == ["a", "c"])
        #expect(out[0].circleId == "mine")
    }

    // MARK: Derived ids

    @Test func derivedCircleIdsComeFromLoadedCircles() {
        let state = loadedState()
        state.networkCircles.append(circle("bobs", owner: "impostor"))   // a later duplicate never wins
        state.circles.append(circle("hidden-mine", owner: me, showOnMap: false))
        state.networkCircles.append(circle("hidden-bobs", owner: "bob", showOnMap: false))

        #expect(state.ownCircleIds == ["mine", "hidden-mine"])
        #expect(state.networkCircleOwners["bobs"] == "bob")
        #expect(state.hiddenCircleIds == ["hidden-mine", "hidden-bobs"])
        let kept = state.excludingHiddenCircles([place("x", circle: "hidden-bobs", addedBy: "bob"), place("y", circle: "bobs", addedBy: "bob"), place("z", circle: nil, addedBy: "bob")])
        #expect(ids(kept) == ["y", "z"])
    }

    @Test func filterContextCombinesStateWithServiceSuppliedIds() {
        let state = loadedState()
        state.selectedConnectionId = "bob"
        state.selectedCategory = .standard(.cafe)
        state.networkCircles.append(circle("hidden-bobs", owner: "bob", showOnMap: false))

        let context = state.placeFilterContext(currentUserId: me, acceptedConnectionUserIds: ["bob"], everyoneAuthorIds: [me, "bob", "followed"])

        #expect(context.selectedConnectionId == "bob")
        #expect(context.selectedCategory == .standard(.cafe))
        #expect(context.currentUserId == me)
        #expect(context.ownCircleIds == ["mine"])
        #expect(context.networkCircleOwners == ["bobs": "bob", "carls": "carl", "mine-shared": me, "hidden-bobs": "bob"])
        #expect(context.hiddenCircleIds == ["hidden-bobs"])
        #expect(context.acceptedConnectionUserIds == ["bob"])
        #expect(context.everyoneAuthorIds == [me, "bob", "followed"])
    }

    // MARK: Category chips

    @Test func availableCategoriesAreSortedUniqueAndClearAStaleSelection() {
        let state = HomeState()
        state.selectedCategory = .standard(.bar)
        let visible = [place("a", circle: nil, addedBy: me, category: .restaurant),
                       place("b", circle: nil, addedBy: me, category: .cafe),
                       place("c", circle: nil, addedBy: me, category: .restaurant)]

        let cleared = state.refreshAvailableCategories(visiblePlaces: visible)

        #expect(state.availableCategories == [.standard(.cafe), .standard(.restaurant)])
        #expect(cleared == .standard(.bar))
        #expect(state.selectedCategory == nil)

        state.selectedCategory = .standard(.cafe)
        #expect(state.refreshAvailableCategories(visiblePlaces: visible) == nil)
        #expect(state.selectedCategory == .standard(.cafe), "a still-offered selection survives")
    }

    // MARK: Connection buckets

    @Test func bucketsAttributeByCircleOwnerAndKeyByConnectionId() {
        let state = loadedState()
        let buckets = state.connectionPlaceBuckets(currentUserId: me, connectionUserIds: ["bob"])

        #expect(ids(buckets.userPlaces) == ["p-mine", "p-mine-shared"], "my circles, including ones that arrived via the network list")
        #expect(ids(buckets.connectionPlaces["bob"] ?? []) == ["p-bob"], "keyed by the connection id even though addedBy is a legacy id")
        #expect(ids(buckets.connectionPlaces["carl"] ?? []) == ["p-carl"], "non-connections key by the circle owner")
        #expect(buckets.connectionPlaces.values.flatMap { $0 }.map { $0.id }.contains("p-orphan") == false, "unloaded circle → no bucket")
    }

    @Test func bucketsSkipHiddenCircles() {
        let state = loadedState()
        state.networkCircles[0] = circle("bobs", owner: "bob", showOnMap: false)
        let buckets = state.connectionPlaceBuckets(currentUserId: me, connectionUserIds: ["bob"])
        #expect(buckets.connectionPlaces["bob"] == nil)
    }

    // MARK: Viewport coverage

    @Test func viewportCoverageIsGeometricAndCapped() {
        let state = HomeState()
        let center = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        #expect(!state.isViewportCovered(center: center, radiusM: 500))

        state.recordFetchedViewport(center: center, radiusM: 2_000)
        #expect(state.isViewportCovered(center: center, radiusM: 500))
        #expect(!state.isViewportCovered(center: center, radiusM: 3_000), "a wider ask isn't covered")
        let farAway = CLLocationCoordinate2D(latitude: 41.0, longitude: -74.0)
        #expect(!state.isViewportCovered(center: farAway, radiusM: 500))

        for i in 0..<HomeState.maxFetchedViewportCircles {
            state.recordFetchedViewport(center: CLLocationCoordinate2D(latitude: 10 + Double(i), longitude: 10), radiusM: 100)
        }
        #expect(state.fetchedViewportCircles.count == HomeState.maxFetchedViewportCircles)
        #expect(!state.isViewportCovered(center: center, radiusM: 500), "the oldest entry was evicted")
    }
}
