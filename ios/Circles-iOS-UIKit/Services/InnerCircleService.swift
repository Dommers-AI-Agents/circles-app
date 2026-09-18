import Foundation

/// The people you've given Inner Circle access to.
///
/// One list per account, reused by every circle, place, moment and check-in set
/// to that tier. The server keeps two invariants we rely on here: only accepted
/// connections may be on it, and access is judged against the current list on
/// every read — so removing someone takes back what they could already see.
struct InnerCircleList: Codable {
    let maxSize: Int
    let userIds: [String]
    let users: [User]

    static let empty = InnerCircleList(maxSize: 150, userIds: [], users: [])
}

private struct InnerCircleResponse: Codable {
    let success: Bool
    let data: InnerCircleList
}

final class InnerCircleService {
    static let shared = InnerCircleService()
    private init() {}

    func getList(completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle", method: .get, body: nil, completion: completion)
    }

    /// Replace the whole list — what the picker's Done button sends. Idempotent,
    /// and the server rejects the lot if any id isn't an accepted connection.
    func replace(userIds: [String], completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle", method: .put, body: ["userIds": userIds], completion: completion)
    }

    func add(userId: String, completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle/\(userId)", method: .post, body: nil, completion: completion)
    }

    func remove(userId: String, completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle/\(userId)", method: .delete, body: nil, completion: completion)
    }

    private func send(endpoint: String,
                      method: RequestMethod,
                      body: [String: Any]?,
                      completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        APIService.shared.request(
            endpoint: endpoint,
            method: method,
            body: body,
            requiresAuth: true
        ) { (result: Result<InnerCircleResponse, APIError>) in
            switch result {
            case .success(let response):
                InnerCircleManager.shared.update(with: response.data)
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
