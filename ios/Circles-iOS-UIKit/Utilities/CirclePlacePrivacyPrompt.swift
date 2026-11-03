import UIKit

/// After a circle's privacy change: if any of the owner's places in it have
/// their own setting, ask whether to make them match (Wes, 2026-11-03). Yes
/// sets them to follow the circle; No keeps each place's own setting, which
/// keeps winning. Silent when there's nothing to ask.
enum CirclePlacePrivacyPrompt {
    private struct CountResponse: Decodable {
        struct Payload: Decodable { let placesWithOwnPrivacy: Int }
        let data: Payload
    }
    private struct MatchResponse: Decodable {
        struct Payload: Decodable { let updated: Int }
        let data: Payload
    }

    static func offer(circleId: String, newPrivacy: PrivacyLevel, from presenter: UIViewController, onMatched: (() -> Void)? = nil) {
        guard let tierTitle = newPrivacy.tier?.title else { return }
        APIService.shared.request(endpoint: "circles/\(circleId)/place-privacy", method: .get, requiresAuth: true) {
            [weak presenter] (result: Result<CountResponse, APIError>) in
            guard case .success(let response) = result, response.data.placesWithOwnPrivacy > 0 else { return }
            let count = response.data.placesWithOwnPrivacy
            DispatchQueue.main.async {
                guard let presenter else { return }
                AlertPresenter.showConfirmation(
                    title: CirclePlacePrivacyCopy.title(count: count, tierTitle: tierTitle),
                    message: CirclePlacePrivacyCopy.message(count: count),
                    confirmTitle: CirclePlacePrivacyCopy.confirm(tierTitle: tierTitle),
                    cancelTitle: CirclePlacePrivacyCopy.keep,
                    from: presenter,
                    onConfirm: {
                        AnalyticsService.shared.logEvent("circle_places_privacy_matched", parameters: ["count": count])
                        APIService.shared.request(endpoint: "circles/\(circleId)/place-privacy/match-circle", method: .post,
                                                  body: [:], requiresAuth: true) { [weak presenter] (result: Result<MatchResponse, APIError>) in
                            DispatchQueue.main.async {
                                guard let presenter else { return }
                                switch result {
                                case .success(let done):
                                    let n = done.data.updated
                                    AlertPresenter.showSuccess("\(n == 1 ? "1 place is" : "\(n) places are") now \(tierTitle)", from: presenter)
                                    NotificationCenter.default.post(name: .refreshCircles, object: nil)
                                    onMatched?()
                                case .failure(let error):
                                    AlertPresenter.showError(error, from: presenter)
                                }
                            }
                        }
                    },
                    onCancel: {
                        AnalyticsService.shared.logEvent("circle_places_privacy_kept", parameters: ["count": count])
                    })
            }
        }
    }
}
