import Foundation

/// Google-backed places: venue fields (name, category, description) come
/// from Google Places and are read-only in the add flow — same rule as the
/// edit screen. Super-users and the venue's verified owner keep full edit
/// access.
enum VenueSourceLock {
    enum Verdict: Equatable {
        /// Not Google-backed, or the user is exempt.
        case unlocked
        /// Lock now; exemption (super-user, ownership) may still be pending.
        case locked
    }

    static func verdict(googlePlaceId: String?, isSuperUser: Bool?, ownedGooglePlaceIds: Set<String>) -> Verdict {
        guard let googlePlaceId = googlePlaceId, !googlePlaceId.isEmpty else { return .unlocked }
        if isSuperUser == true || ownedGooglePlaceIds.contains(googlePlaceId) { return .unlocked }
        return .locked
    }
}
