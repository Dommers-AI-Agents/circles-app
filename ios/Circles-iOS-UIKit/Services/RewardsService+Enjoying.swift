import Foundation

/// "Enjoying <store>?" after a reward is given, and private feedback to the
/// store (2026-11-02). Server: services/storeFeedback.js.
struct EnjoyingCardData: Codable, Equatable {
    let show: Bool
    let venueName: String?
    /// The store's canonical place (follow)
    let globalPlaceId: String?
    /// A save of the store the customer can comment on (review, moment)
    let reviewPlaceId: String?
    let following: Bool?
}

struct StoreFeedbackEntry: Codable, Equatable {
    struct Card: Codable, Equatable {
        let id: String
        let displayName: String
        let profilePicture: String?
    }
    let rating: Int
    let note: String?
    let createdAt: String?
    let user: Card?
}

private struct StoreFeedbackListData: Codable { let feedback: [StoreFeedbackEntry] }
private struct StoreFeedbackSentData: Codable { let sent: Bool }

extension RewardsService {

    /// The card's data the first time only for this store (`show` false after)
    func enjoyingCard(venueId: String, completion: @escaping (Result<EnjoyingCardData, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/enjoying", method: .post, requiresAuth: true) {
            (result: Result<RewardsEnvelope<EnjoyingCardData>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func sendStoreFeedback(venueId: String, rating: Int, note: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        var body: [String: Any] = ["rating": rating]
        if let note, !note.isEmpty { body["note"] = note }
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/feedback", method: .post, body: body, requiresAuth: true) {
            (result: Result<RewardsEnvelope<StoreFeedbackSentData>, APIError>) in
            completion(result.map { _ in () }.mapError { $0 as Error })
        }
    }

    /// The store team's private feedback, newest first
    func fetchStoreFeedback(venueId: String, completion: @escaping (Result<[StoreFeedbackEntry], Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/feedback", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<StoreFeedbackListData>, APIError>) in
            completion(result.map(\.data.feedback).mapError { $0 as Error })
        }
    }
}
