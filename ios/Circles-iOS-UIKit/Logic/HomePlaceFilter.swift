import Foundation

/// The home map's place scoping: which of the loaded places show for the
/// current people selection and category chip.
///
/// Extracted from `CirclesHomeViewController.applyFiltersToPlaces` so the
/// rules are unit tested. The controller builds a `Context` from its state
/// and the shared services; nothing in here touches a service or a view.
///
/// People selection (`selectedConnectionId`):
/// - `nil` = "Everyone": your own places, your accepted connections' and
///   everyone you follow (`everyoneAuthorIds`).
/// - `my_places_only`: places in your own circles, or in circles you own
///   that arrived via the network list.
/// - `my_connections_only`: accepted connections only.
/// - anything else: that one person.
///
/// A place is attributed to its circle's owner when the circle is known,
/// else to whoever added it (viewport-fetched places may arrive before
/// their circle metadata). Circles the owner toggled off the home map are
/// dropped first; the category chip is applied last.
struct HomePlaceFilter {
    static let myPlacesOnlyId = "my_places_only"
    static let myConnectionsOnlyId = "my_connections_only"

    struct Context {
        var selectedConnectionId: String? = nil
        var selectedCategory: UnifiedCategory? = nil
        var currentUserId: String = ""
        /// Ids of the user's own circles.
        var ownCircleIds: Set<String> = []
        /// circleId → owner user id, for every network circle loaded.
        var networkCircleOwners: [String: String] = [:]
        /// Circles hidden from the home map (`showOnMap == false`), own or network.
        var hiddenCircleIds: Set<String> = []
        var acceptedConnectionUserIds: [String] = []
        var everyoneAuthorIds: Set<String> = []
    }

    /// Circles whose owner toggled them off the home map.
    static func hiddenCircleIds(in circles: [Circle]) -> Set<String> {
        Set(circles.filter { $0.showOnMap == false }.map { $0.id })
    }

    static func excludingHiddenCircles(_ places: [Place], hiddenIds: Set<String>) -> [Place] {
        guard !hiddenIds.isEmpty else { return places }
        return places.filter { place in
            guard let circleId = place.circleId else { return true }
            return !hiddenIds.contains(circleId)
        }
    }

    static func apply(_ input: [Place], context: Context) -> [Place] {
        let places = excludingHiddenCircles(input, hiddenIds: context.hiddenCircleIds)

        /// Owner of the place's circle when known, else who added it.
        func author(of place: Place) -> String? {
            if let circleId = place.circleId, let owner = context.networkCircleOwners[circleId] {
                return owner
            }
            return place.addedBy
        }

        var scoped: [Place]
        if let connectionId = context.selectedConnectionId {
            if connectionId == myPlacesOnlyId {
                if context.ownCircleIds.isEmpty && context.networkCircleOwners.isEmpty {
                    scoped = []
                } else {
                    scoped = places.filter { place in
                        if let circleId = place.circleId, context.ownCircleIds.contains(circleId) {
                            return true
                        }
                        if let circleId = place.circleId, let owner = context.networkCircleOwners[circleId] {
                            return IDNormalizer.isSameUser(owner, context.currentUserId)
                        }
                        return false
                    }
                }
            } else if connectionId == myConnectionsOnlyId {
                let connected = context.acceptedConnectionUserIds
                scoped = places.filter { place in
                    let who = author(of: place)
                    return connected.contains { IDNormalizer.isSameUser(who, $0) }
                }
            } else {
                scoped = places.filter { IDNormalizer.isSameUser(author(of: $0), connectionId) }
            }
        } else {
            let authors = context.everyoneAuthorIds
            scoped = places.filter { place in
                let who = author(of: place)
                return authors.contains { IDNormalizer.isSameUser(who, $0) }
            }
        }

        if let category = context.selectedCategory {
            scoped = scoped.filter { category.matches(place: $0) }
        }
        return scoped
    }
}
