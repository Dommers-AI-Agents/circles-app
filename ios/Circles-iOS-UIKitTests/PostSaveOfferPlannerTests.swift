import Foundation
import Testing
@testable import Circles_iOS

/// Precedence for the beat after a place is saved: at most one nudge, and the
/// rewards (coin drop, milestone badge) are never talked over.
struct PostSaveOfferPlannerTests {
    private func context(
        placeHasPhoto: Bool = true,
        postcardEligible: Bool = true,
        distance: Double? = nil,
        milestone: Bool = false,
        clear: Bool = true
    ) -> PostSaveOfferPlanner.Context {
        PostSaveOfferPlanner.Context(
            placeHasPhoto: placeHasPhoto,
            postcardEligible: postcardEligible,
            distanceToPlaceMeters: distance,
            isCelebratingMilestone: milestone,
            screenIsClear: clear
        )
    }

    @Test func standingInThePlaceAsksToCheckIn() {
        #expect(PostSaveOfferPlanner.decide(context(distance: 0)) == .checkIn)
        #expect(PostSaveOfferPlanner.decide(context(distance: 50)) == .checkIn)
        // Check-in wins even when a postcard would also have qualified.
        #expect(PostSaveOfferPlanner.decide(context(postcardEligible: true, distance: 12)) == .checkIn)
        // ...and is still offered for a place with no photo at all.
        #expect(PostSaveOfferPlanner.decide(context(placeHasPhoto: false, postcardEligible: false, distance: 12)) == .checkIn)
    }

    @Test func anywhereElseOffersThePostcard() {
        #expect(PostSaveOfferPlanner.decide(context(distance: 51)) == .postcard)
        #expect(PostSaveOfferPlanner.decide(context(distance: 40_000)) == .postcard)
        // Unknown location is the common case: no fix, no permission, or a
        // place with no coordinates.
        #expect(PostSaveOfferPlanner.decide(context(distance: nil)) == .postcard)
    }

    @Test func aPostcardNeedsAPhotoAndAnUnspentCooldown() {
        #expect(PostSaveOfferPlanner.decide(context(placeHasPhoto: false)) == .none)
        #expect(PostSaveOfferPlanner.decide(context(postcardEligible: false)) == .none)
    }

    @Test func aMilestoneBadgeSilencesThePostcardButNotACheckIn() {
        #expect(PostSaveOfferPlanner.decide(context(milestone: true)) == .none)
        #expect(PostSaveOfferPlanner.decide(context(distance: 10, milestone: true)) == .checkIn)
    }

    @Test func nothingIsAskedOverAnotherScreen() {
        #expect(PostSaveOfferPlanner.decide(context(clear: false)) == .none)
        #expect(PostSaveOfferPlanner.decide(context(distance: 5, clear: false)) == .none)
    }
}
