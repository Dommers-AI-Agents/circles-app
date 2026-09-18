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

    /// `ownPhotoUrl` is the picture the user themselves added with this save,
    /// when there was one — the composer opens on that rather than whichever
    /// photo happens to sort first, which is often the venue's stock one.
    static func offer(place: Place, ownPhotoUrl: String?, postcardEligible: Bool, milestoneShown: Bool) {
        // The location fix is the slow part and it is what decides between the
        // two offers, so start it first and ask once it is in.
        distanceToPlace(place) { distance in
            DispatchQueue.main.asyncAfter(deadline: .now() + offerDelay) {
                guard let presenter = topPresenter() else { return }
                let decision = PostSaveOfferPlanner.decide(
                    PostSaveOfferPlanner.Context(
                        hasOwnPhoto: !(ownPhotoUrl ?? "").isEmpty,
                        postcardEligible: postcardEligible,
                        distanceToPlaceMeters: distance,
                        isCelebratingMilestone: milestoneShown,
                        screenIsClear: isClear(presenter)
                    )
                )
                switch decision {
                case .checkIn: presentCheckInOffer(place: place, from: presenter)
                case .postcard: presentPostcardOffer(place: place, photoUrl: ownPhotoUrl, from: presenter)
                case .none: break
                }
            }
        }
    }

    /// The photo-upload moment. No location fix, no milestone to dodge, and
    /// no doubt about whose picture it is — the user just took or picked it,
    /// and it is already in memory, so the composer opens on it instantly.
    /// Returns whether it asked; the caller shows its own confirmation if not.
    @discardableResult
    static func offerAfterPhotoUpload(place: Place, photo: UIImage, eligible: Bool,
                                      from presenter: UIViewController) -> Bool {
        guard eligible else {
            Logger.debug("📮 postcard offer skipped: server says the cooldown is spent")
            return false
        }
        guard isClear(presenter) else {
            Logger.debug("📮 postcard offer skipped: \(type(of: presenter)) is not a usable presenter")
            return false
        }
        let key = HomePromptService.postcardNudgeKey
        whenFree(presenter) { presenter in
        AnalyticsService.shared.logEvent("postcard_nudge_shown", parameters: ["source": "photo_upload"])
        AlertPresenter.showConfirmation(
            title: "Photo added to \(place.name)",
            message: "Want to send it as a postcard?",
            confirmTitle: "Make One",
            cancelTitle: "Not Now",
            from: presenter,
            onConfirm: {
                AnalyticsService.shared.logEvent("postcard_nudge_accepted", parameters: ["source": "photo_upload"])
                HomePromptService.shared.ack(key: key, action: .acted)
                PostcardComposerRouter.open(photo: photo, place: place, from: presenter)
            },
            onCancel: {
                AnalyticsService.shared.logEvent("postcard_nudge_declined", parameters: ["source": "photo_upload"])
                HomePromptService.shared.ack(key: key, action: .skipped)
            }
        )
        }
        return true
    }

    // MARK: - The two questions

    private static func presentCheckInOffer(place: Place, from presenter: UIViewController) {
        whenFree(presenter) { presenter in
        AlertPresenter.showConfirmation(
            title: "You're at \(place.name)",
            message: "Check in and let your people know?",
            confirmTitle: "Check In",
            cancelTitle: "Not Now",
            from: presenter,
            onConfirm: { CheckInViewController.present(from: presenter, prefilledPlace: place) }
        )
        }
    }

    private static func presentPostcardOffer(place: Place, photoUrl: String?, from presenter: UIViewController) {
        let key = HomePromptService.postcardNudgeKey
        whenFree(presenter) { presenter in
        AnalyticsService.shared.logEvent("postcard_nudge_shown", parameters: ["source": "post_save"])
        AlertPresenter.showConfirmation(
            title: "Send a postcard from \(place.name)?",
            message: "Put a photo of \(place.name) on a card and send it to someone.",
            confirmTitle: "Make One",
            cancelTitle: "Not Now",
            from: presenter,
            onConfirm: {
                AnalyticsService.shared.logEvent("postcard_nudge_accepted", parameters: ["source": "post_save"])
                // Acked either way: being asked is what spends the fortnight,
                // and the home card reads the same key.
                HomePromptService.shared.ack(key: key, action: .acted)
                PostcardComposerRouter.open(
                    photoUrl: photoUrl,
                    place: PostcardComposerRouter.widgetPlace(for: place),
                    from: presenter
                )
            },
            onCancel: {
                AnalyticsService.shared.logEvent("postcard_nudge_declined", parameters: ["source": "post_save"])
                HomePromptService.shared.ack(key: key, action: .skipped)
            }
        )
        }
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

    /// Whatever is frontmost — the add-place flow may still be on screen, and
    /// presenting from the root while it is would put the alert underneath it.
    private static func topPresenter() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    /// Named rather than `presentedViewController == nil`, which is always
    /// true of the topmost controller and so guards nothing. What actually
    /// matters: don't stack on another question, don't talk over the badge
    /// celebration, and don't attach an alert to a screen that is leaving.
    private static func isClear(_ presenter: UIViewController) -> Bool {
        if presenter is UIAlertController { return false }
        if presenter is MilestoneCelebrationViewController { return false }
        if presenter.isBeingDismissed { return false }
        return true
    }

    /// Presents once the presenter can actually present.
    ///
    /// `AlertPresenter` calls `present` with no guard, and UIKit drops a
    /// present on a controller that is already presenting — it logs a warning
    /// and nothing appears. That is how this offer went missing after a photo
    /// upload: the alert was built and thrown at a screen still finishing with
    /// the upload's loading alert, and the user saw nothing at all. Waiting a
    /// few runloop turns for the screen to free up costs nothing and turns a
    /// silent miss into a shown question.
    private static func whenFree(_ presenter: UIViewController,
                                 attempt: Int = 0,
                                 _ show: @escaping (UIViewController) -> Void) {
        guard presenter.view.window != nil else {
            Logger.debug("📮 postcard offer skipped: presenter left the window")
            return
        }
        if presenter.presentedViewController == nil {
            show(presenter)
            return
        }
        guard attempt < 12 else {          // ~3s, then give up rather than pile on
            Logger.debug("📮 postcard offer skipped: screen stayed busy")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            whenFree(presenter, attempt: attempt + 1, show)
        }
    }
}
