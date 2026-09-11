import Testing
@testable import Circles_iOS

/// When the add-place form locks Google-sourced venue fields.
struct VenueSourceLockTests {
    @Test func onlyGoogleBackedPlacesLock() {
        #expect(VenueSourceLock.verdict(googlePlaceId: nil, isSuperUser: nil, ownedGooglePlaceIds: []) == .unlocked)
        #expect(VenueSourceLock.verdict(googlePlaceId: "", isSuperUser: nil, ownedGooglePlaceIds: []) == .unlocked)
        #expect(VenueSourceLock.verdict(googlePlaceId: "g1", isSuperUser: nil, ownedGooglePlaceIds: []) == .locked)
    }

    @Test func superUsersAndOwnersAreExempt() {
        #expect(VenueSourceLock.verdict(googlePlaceId: "g1", isSuperUser: true, ownedGooglePlaceIds: []) == .unlocked)
        #expect(VenueSourceLock.verdict(googlePlaceId: "g1", isSuperUser: false, ownedGooglePlaceIds: ["g1"]) == .unlocked)
        // Owning a different venue doesn't help, and an unknown super-user
        // status still locks until resolved
        #expect(VenueSourceLock.verdict(googlePlaceId: "g1", isSuperUser: false, ownedGooglePlaceIds: ["g2"]) == .locked)
        #expect(VenueSourceLock.verdict(googlePlaceId: "g1", isSuperUser: nil, ownedGooglePlaceIds: ["g2"]) == .locked)
    }
}
