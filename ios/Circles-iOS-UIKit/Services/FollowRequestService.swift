import Foundation

/// Someone asking to follow a private profile.
struct FollowRequest: Codable, Identifiable {
    let requesterId: String
    let createdAt: String?
    let user: User
    var id: String { requesterId }
}

private struct FollowRequestsResponse: Codable {
    let success: Bool
    let requests: [FollowRequest]
}

private struct ProfilePrivacyResponse: Codable {
    let success: Bool
    let profilePrivate: Bool
    let acceptedRequests: Int?
}

/// Private profiles (Wes, 2026-11-02): the switch in Settings, and the
/// requests waiting for the owner's yes. Following itself goes through
/// `users/:id/follow`, which answers `requested: true` for a private profile.
final class FollowRequestService {
    static let shared = FollowRequestService()
    private init() {}

    /// Requests waiting on me, as last loaded (Settings shows the count).
    private(set) var pendingCount = 0

    func setProfilePrivate(_ isPrivate: Bool, completion: @escaping (Result<Int, APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/profile-privacy",
            method: .put,
            body: ["private": isPrivate],
            requiresAuth: true
        ) { (result: Result<ProfilePrivacyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let me = AuthService.shared.currentUser {
                        AuthService.shared.updateCurrentUser(me.copy(profilePrivate: response.profilePrivate))
                    }
                    if !response.profilePrivate { self.pendingCount = 0 }
                    completion(.success(response.acceptedRequests ?? 0))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func fetchRequests(completion: @escaping (Result<[FollowRequest], APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/follow-requests",
            method: .get,
            requiresAuth: true
        ) { (result: Result<FollowRequestsResponse, APIError>) in
            DispatchQueue.main.async {
                if case .success(let response) = result { self.pendingCount = response.requests.count }
                completion(result.map(\.requests))
            }
        }
    }

    func accept(_ requesterId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        answer(requesterId, action: "accept", completion: completion)
    }

    func decline(_ requesterId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        answer(requesterId, action: "decline", completion: completion)
    }

    private func answer(_ requesterId: String, action: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/follow-requests/\(requesterId)/\(action)",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                if case .success = result { self.pendingCount = max(0, self.pendingCount - 1) }
                completion(result.map { _ in () })
            }
        }
    }
}
