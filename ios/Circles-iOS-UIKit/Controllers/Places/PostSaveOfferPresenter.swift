import UIKit
import CoreLocation

/// Runs the beat after a place is saved: one location fix, one decision
/// (`PostSaveOfferPlanner`), at most one question. Static and window-based
/// rather than a method on the add-place screen, because that screen is busy
/// dismissing itself while this runs.
enum PostSaveOfferPresenter {
    /// Long enough for the add-place flow to finish dismissing. Called after
    /// the coin drop has already played, so this is measured from there.
    static let offerDelay: TimeInterval = 1.5

    static func offer(place: Place, postcardEligible: Bool, milestoneShown: Bool) {
        // The location fix is the slow part and it is what decides between the
        // two offers, so start it first and ask once it is in.
        distanceToPlace(place) { distance in
            DispatchQueue.main.asyncAfter(deadline: .now() + offerDelay) {
                guard let presenter = rootPresenter() else { return }
                let decision = PostSaveOfferPlanner.decide(
                    PostSaveOfferPlanner.Context(
                        placeHasPhoto: !(place.photos ?? []).isEmpty,
                        postcardEligible: postcardEligible,
                        distanceToPlaceMeters: distance,
                        isCelebratingMilestone: milestoneShown,
                        // Anything presented over the root — a milestone, a
                        // sheet, the add-place flow still going away — means
                        // this is not our moment.
                        screenIsClear: presenter.presentedViewController == nil
                    )
                )
                switch decision {
                case .checkIn: presentCheckInOffer(place: place, from: presenter)
                case .postcard: presentPostcardOffer(place: place, from: presenter)
                case .none: break
                }
            }
        }
    }

    // MARK: - The two questions

    private static func presentCheckInOffer(place: Place, from presenter: UIViewController) {
        AlertPresenter.showConfirmation(
            title: "You're at \(place.name)",
            message: "Check in and let your people know?",
            confirmTitle: "Check In",
            cancelTitle: "Not Now",
            from: presenter,
            onConfirm: { CheckInViewController.present(from: presenter, prefilledPlace: place) }
        )
    }

    private static func presentPostcardOffer(place: Place, from presenter: UIViewController) {
        let key = HomePromptService.postcardNudgeKey
        AnalyticsService.shared.logEvent("postcard_nudge_shown", parameters: ["source": "post_save"])
        AlertPresenter.showConfirmation(
            title: "Send a postcard from \(place.name)?",
            message: "Put the photo you just added on a card and send it to someone.",
            confirmTitle: "Make One",
            cancelTitle: "Not Now",
            from: presenter,
            onConfirm: {
                AnalyticsService.shared.logEvent("postcard_nudge_accepted", parameters: ["source": "post_save"])
                // Acked either way: being asked is what spends the fortnight,
                // and the home card reads the same key.
                HomePromptService.shared.ack(key: key, action: .acted)
                PostcardComposerRouter.open(place: place, from: presenter)
            },
            onCancel: {
                AnalyticsService.shared.logEvent("postcard_nudge_declined", parameters: ["source": "post_save"])
                HomePromptService.shared.ack(key: key, action: .skipped)
            }
        )
    }

    // MARK: - Helpers

    /// nil when we have no fix or the place has no coordinates — "not standing
    /// there", which is the right default for both offers.
    private static func distanceToPlace(_ place: Place, completion: @escaping (Double?) -> Void) {
        guard let placeLocation = place.location?.clLocation else {
            completion(nil)
            return
        }
        LocationService.shared.getCurrentLocation { current in
            completion(current.map { $0.distance(from: placeLocation) })
        }
    }

    private static func rootPresenter() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
