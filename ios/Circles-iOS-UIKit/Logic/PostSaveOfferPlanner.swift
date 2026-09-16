import Foundation

/// What the app may offer in the beat after a place is saved.
///
/// Three things already want that moment — the coin drop, a milestone badge,
/// and (rarely) "you're standing here, check in?" — so a fourth needs a
/// referee rather than another `present` call. Exactly one *nudge* is allowed
/// per save, and the rewards always win: a badge the user just earned is not
/// something to talk over.
enum PostSaveOffer: Equatable {
    case checkIn
    case postcard
    case none
}

/// Pure decision, so the precedence is testable without a device, a location
/// fix, or a view hierarchy.
enum PostSaveOfferPlanner {
    /// Same radius the check-in flow has always used for "you are here".
    static let atPlaceRadiusMeters: Double = 50

    struct Context: Equatable {
        /// The save has a photo to put on a card — the composer opens on a
        /// picture or not at all.
        var placeHasPhoto: Bool
        /// The server's fortnightly cooldown says we may ask.
        var postcardEligible: Bool
        /// Metres from the user to the place; nil when location is unknown,
        /// which is the common case and simply means "not standing there".
        var distanceToPlaceMeters: Double?
        /// A milestone celebration is on screen for this save.
        var isCelebratingMilestone: Bool
        /// Nothing else is presented right now.
        var screenIsClear: Bool
    }

    static func decide(_ context: Context) -> PostSaveOffer {
        guard context.screenIsClear else { return .none }

        // Standing in the place beats everything else we could ask: it is the
        // rarer moment and the more useful one.
        if let distance = context.distanceToPlaceMeters, distance <= atPlaceRadiusMeters {
            return .checkIn
        }

        // A postcard needs a picture, an unspent cooldown, and a quiet screen.
        // Yielding to the badge costs nothing: the cooldown is only spent when
        // the question is actually asked, so the nudge comes back another day.
        guard context.postcardEligible, context.placeHasPhoto, !context.isCelebratingMilestone else {
            return .none
        }
        return .postcard
    }
}
