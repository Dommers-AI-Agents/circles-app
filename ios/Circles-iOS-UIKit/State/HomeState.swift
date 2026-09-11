import Foundation
import CoreLocation

/// The home screen's data + selection state, owned by `CirclesHomeViewController`
/// and (from Phase 4 step 3) written by the home data loader.
///
/// This holds what the home map/list/search render FROM: the loaded circles
/// and places, the people/category selection and the search overlay's working
/// set. Loading flags, timers, work items and views stay on the controller.
/// The controller exposes every property here through forwarding computed
/// properties so existing call sites read unchanged.
///
/// Everything in here is pure state or pure derivation over that state — no
/// services, no views — so the rules are unit tested (`HomeStateTests`).
final class HomeState {

    // MARK: - Circles

    /// The user's own circles, in profile order (never re-sorted here).
    var circles: [Circle] = []
    /// Circles loaded from connections/followed people (`network/my-network-circles`
    /// plus per-connection fetches). May contain the user's own circles when
    /// they arrive via the network list.
    var networkCircles: [Circle] = []
    var isShowingNetworkCircles = false

    // MARK: - Places

    /// Every place loaded so far (own + network + viewport), deduplicated by id.
    var allPlaces: [Place] = []
    /// The user's own places only. Changing this notifies the embedded map so
    /// it can center on the user's favorites (see `onUserOwnPlacesChanged`).
    var userOwnPlaces: [Place] = [] {
        didSet { onUserOwnPlacesChanged?(userOwnPlaces) }
    }
    /// Fired on every write to `userOwnPlaces`, whoever writes it.
    var onUserOwnPlacesChanged: (([Place]) -> Void)?
    /// Network places fetched for search (the search overlay's second source).
    var networkPlaces: [Place] = []

    // MARK: - Instance cache

    var cachedPlaces: [Place] = []
    var placesCacheExpiry: Date?
    let cacheExpiryMinutes: TimeInterval = 5

    /// Connections whose FULL place set has been loaded (not viewport-bounded),
    /// so the All Connections prefetch doesn't refetch on every selection.
    var prefetchedConnectionIds = Set<String>()
    /// Viewport regions already fetched (center + radius) so panning within a
    /// covered area doesn't refetch. Capped at `maxFetchedViewportCircles`.
    var fetchedViewportCircles: [(center: CLLocationCoordinate2D, radiusM: Double)] = []
    static let maxFetchedViewportCircles = 50
    /// Guards the disk-cache paint so it happens at most once per instance.
    var hasPaintedPlacesFromDiskCache = false

    // MARK: - Selection

    /// `nil` = Everyone; `HomePlaceFilter.myPlacesOnlyId` / `.myConnectionsOnlyId`
    /// are pseudo ids; anything else is one person's user id.
    var selectedConnectionId: String? = nil
    /// Set only when a specific connection is filtered.
    var selectedConnectionUser: User? = nil
    var selectedCategory: UnifiedCategory?
    /// Category chips offered for the current people selection.
    var availableCategories: [UnifiedCategory] = []

    // MARK: - Search overlay

    /// While `isSearching`, the SEARCH-RESULTS array the overlay table renders
    /// and indexes into. Map-refresh paths must never write it during a search.
    var filteredPlaces: [Place] = []
    var isSearching = false
    /// User tapped Done/the map to drop the people/suggested dropdown — it
    /// stays down until they edit the query or refocus the bar.
    var isSearchOverlayDismissed = false
    var currentSearchScope: SearchScope = .myPlaces
    /// People results (the PEOPLE section of the search overlay).
    var searchedUsers: [User] = []
    /// Meters from the search reference location, keyed by place id, for the PLACES rows.
    var searchDistances: [String: CLLocationDistance] = [:]
    /// Global venues suggested when the query matches nothing saved.
    var suggestedPlaces: [GlobalPlace] = []
    var suggestedDistances: [String: CLLocationDistance] = [:]

    // MARK: - Cache rules

    var isCacheValid: Bool {
        guard let expiry = placesCacheExpiry else { return false }
        return Date() < expiry && !cachedPlaces.isEmpty
    }

    func invalidateCache() {
        cachedPlaces.removeAll()
        userOwnPlaces.removeAll()
        placesCacheExpiry = nil
    }

    /// Stores `places` as the cache and restarts the expiry window.
    func cache(_ places: [Place], now: Date = Date()) {
        cachedPlaces = places
        placesCacheExpiry = now.addingTimeInterval(cacheExpiryMinutes * 60)
    }

    /// Remembers a fully-covered viewport fetch, dropping the oldest past the cap.
    func recordFetchedViewport(center: CLLocationCoordinate2D, radiusM: Double) {
        fetchedViewportCircles.append((center: center, radiusM: radiusM))
        if fetchedViewportCircles.count > Self.maxFetchedViewportCircles {
            fetchedViewportCircles.removeFirst()
        }
    }

    /// True when an earlier, complete viewport fetch already covers a circle
    /// of `radiusM` around `center`.
    func isViewportCovered(center: CLLocationCoordinate2D, radiusM: Double) -> Bool {
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return fetchedViewportCircles.contains { fetched in
            let prev = CLLocation(latitude: fetched.center.latitude, longitude: fetched.center.longitude)
            return prev.distance(from: location) + radiusM <= fetched.radiusM
        }
    }

    // MARK: - Deduplication

    /// First occurrence of each place id wins, order preserved.
    static func dedupe(_ places: [Place]) -> [Place] {
        var seen = Set<String>()
        return places.filter { seen.insert($0.id).inserted }
    }

    /// Own places first (they win over network copies of the same id).
    static func merge(userPlaces: [Place], networkPlaces: [Place]) -> [Place] {
        dedupe(userPlaces + networkPlaces)
    }

    // MARK: - Derived state

    /// Ids of the user's own circles.
    var ownCircleIds: Set<String> { Set(circles.map { $0.id }) }

    /// circleId → owner for every network circle loaded; the first copy of a
    /// circle id wins, matching the order they were appended.
    var networkCircleOwners: [String: String] {
        var owners: [String: String] = [:]
        for circle in networkCircles where owners[circle.id] == nil { owners[circle.id] = circle.owner }
        return owners
    }

    /// Circles hidden from the home map (`showOnMap == false`), own or network.
    var hiddenCircleIds: Set<String> {
        HomePlaceFilter.hiddenCircleIds(in: circles + networkCircles)
    }

    func excludingHiddenCircles(_ places: [Place]) -> [Place] {
        HomePlaceFilter.excludingHiddenCircles(places, hiddenIds: hiddenCircleIds)
    }

    /// Everything `HomePlaceFilter` needs, read once per filter pass. The
    /// caller supplies what lives in the auth/network services.
    func placeFilterContext(currentUserId: String,
                            acceptedConnectionUserIds: [String],
                            everyoneAuthorIds: Set<String>) -> HomePlaceFilter.Context {
        var context = HomePlaceFilter.Context()
        context.selectedConnectionId = selectedConnectionId
        context.selectedCategory = selectedCategory
        context.currentUserId = currentUserId
        context.ownCircleIds = ownCircleIds
        context.networkCircleOwners = networkCircleOwners
        context.hiddenCircleIds = hiddenCircleIds
        context.acceptedConnectionUserIds = acceptedConnectionUserIds
        context.everyoneAuthorIds = everyoneAuthorIds
        return context
    }

    /// Recomputes `availableCategories` from the places visible under the
    /// current people selection, sorted by display name. Clears
    /// `selectedCategory` when it is no longer offered.
    /// - Returns: the category that was cleared, if any.
    @discardableResult
    func refreshAvailableCategories(visiblePlaces: [Place]) -> UnifiedCategory? {
        let categories = Set(visiblePlaces.map { UnifiedCategory.from(place: $0) })
        availableCategories = Array(categories).sorted { $0.displayName < $1.displayName }
        if let selected = selectedCategory, !availableCategories.contains(selected) {
            selectedCategory = nil
            return selected
        }
        return nil
    }

    /// Buckets `allPlaces` (minus hidden circles) into the user's own places
    /// and per-connection lists keyed by the connection's user id. The
    /// circle owner is authoritative — `place.addedBy` can carry a
    /// connection's legacy account id. Places whose circle isn't loaded are
    /// left out of both.
    func connectionPlaceBuckets(currentUserId: String,
                                connectionUserIds: [String]) -> (userPlaces: [Place], connectionPlaces: [String: [Place]]) {
        var userPlaces: [Place] = []
        var connectionPlaces: [String: [Place]] = [:]
        let userCircleIds = ownCircleIds

        // Circle owner id → connection user id, tolerating id-format drift.
        var ownerToConnectionId: [String: String] = [:]
        for otherUserId in connectionUserIds {
            for circle in networkCircles where IDNormalizer.isSameUser(circle.owner, otherUserId) {
                ownerToConnectionId[circle.owner] = otherUserId
            }
        }

        for place in excludingHiddenCircles(allPlaces) {
            guard let circleId = place.circleId else { continue }
            if userCircleIds.contains(circleId) {
                userPlaces.append(place)
            } else if let circle = networkCircles.first(where: { $0.id == circleId }) {
                if IDNormalizer.isSameUser(circle.owner, currentUserId) {
                    userPlaces.append(place)
                } else {
                    let key = ownerToConnectionId[circle.owner] ?? circle.owner
                    connectionPlaces[key, default: []].append(place)
                }
            }
        }
        return (userPlaces, connectionPlaces)
    }

}
