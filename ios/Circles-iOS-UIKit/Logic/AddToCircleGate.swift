import Foundation

/// Whether the place page offers "Add to Circle". Hidden when the user
/// created the place, has no circles, or already saved this venue — where
/// "already saved" must match by venue identity, not save-doc id: arriving
/// from the activity feed, the screen holds ANOTHER user's copy of a venue
/// the current user may also have saved.
enum AddToCircleGate {
    enum Verdict: Equatable {
        case hide
        case show
        /// The user has circles and none holds this exact doc; the caller
        /// must fetch their places and run `verdictAfterVenueCheck`.
        case checkVenueMatch(circleIds: [String])
    }

    /// The user created this place themselves.
    static func isOwnSave(_ place: Place, currentUserId: String) -> Bool {
        place.addedBy == currentUserId
    }

    /// Given the user's circles: no circles → hide; a circle already holds
    /// this doc id → hide; otherwise the venue check is still needed.
    static func verdict(for place: Place, in circles: [Circle]) -> Verdict {
        guard !circles.isEmpty else { return .hide }
        // Same doc id in a circle = definitely already saved
        if circles.contains(where: { $0.places?.contains(place.id) ?? false }) {
            return .hide
        }
        return .checkVenueMatch(circleIds: circles.map(\.id))
    }

    /// Given the user's saved places: hide when one is the same venue.
    static func verdictAfterVenueCheck(for place: Place, myPlaces: [Place]) -> Verdict {
        myPlaces.contains(where: { isSameVenue(place, as: $0) }) ? .hide : .show
    }

    /// Is `other` (one of the current user's saved places) the same real-world
    /// venue as `place`? Ids first, then name+address.
    static func isSameVenue(_ place: Place, as other: Place) -> Bool {
        if let gpid = place.googlePlaceId, !gpid.isEmpty, other.googlePlaceId == gpid {
            return true
        }
        if let globalId = place.globalPlaceId, !globalId.isEmpty,
           other.globalPlaceId == globalId || other.id == globalId {
            return true
        }
        // The screen may hold a converted GlobalPlace whose id IS the global id
        if other.globalPlaceId == place.id {
            return true
        }
        let normalize = { (s: String) in s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        return normalize(other.name) == normalize(place.name)
            && !place.address.isEmpty
            && normalize(other.address) == normalize(place.address)
    }
}
