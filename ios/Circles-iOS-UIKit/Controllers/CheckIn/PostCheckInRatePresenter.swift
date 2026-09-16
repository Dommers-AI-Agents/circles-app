import UIKit

/// After a check-in lands: "How was <place> this time?" — one tap updates the
/// saver's rating (latest wins, history kept), Skip keeps the current score.
/// Static and window-based like `PostSaveOfferPresenter`, because the
/// check-in flow is still dismissing itself when the API reply arrives.
enum PostCheckInRatePresenter {
    static let pollInterval: TimeInterval = 0.5
    static let maxPolls = 120 // ~60s: the check-in success alert waits for a tap

    static func offer(placeId: String, checkInId: String, placeName: String) {
        waitForClearScreen(remaining: maxPolls) { presenter in
            PlaceService.shared.fetchPlaceById(id: placeId) { result in
                DispatchQueue.main.async {
                    guard case .success(let place) = result,
                          place.isAddedByCurrentUser,
                          RatingHistoryFormatter.shouldPromptAfterCheckIn(userRatedAt: place.userRatedAt),
                          presenter.presentedViewController == nil else { return }
                    present(place: place, checkInId: checkInId, from: presenter)
                }
            }
        }
    }

    private static func present(place: Place, checkInId: String, from presenter: UIViewController) {
        let sheet = PlaceRatingSheetViewController(
            placeName: place.name,
            title: "How was \(place.name) this time?",
            subtitle: RatingHistoryFormatter.recheckSubtitle(current: place.userRating),
            currentRating: place.userRating
        )
        sheet.onContinue = { rating in
            guard let rating = rating else { return }
            PlaceService.shared.updatePlace(id: place.id, userRating: rating, ratingCheckInId: checkInId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let updated):
                        NotificationCenter.default.post(name: .placeRatingChanged, object: nil,
                                                        userInfo: ["placeId": updated.id, "place": updated])
                    case .failure(let error):
                        if let top = rootPresenter() { AlertPresenter.showError(error, from: top) }
                    }
                }
            }
        }
        PlaceRatingSheetViewController.present(sheet, from: presenter)
    }

    private static func waitForClearScreen(remaining: Int, then: @escaping (UIViewController) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            guard remaining > 0, let presenter = rootPresenter() else { return }
            if presenter.presentedViewController == nil {
                then(presenter)
            } else {
                waitForClearScreen(remaining: remaining - 1, then: then)
            }
        }
    }

    private static func rootPresenter() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
            // Never over the splash/login screen (cold launch from a notification)
            .flatMap { $0 is CirclesTabBarController ? $0 : nil }
    }
}
