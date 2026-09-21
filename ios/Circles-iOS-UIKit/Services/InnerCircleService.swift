import Foundation

/// One named set of people you've given Inner Circle access to.
struct InnerCircleNamedList: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let userIds: [String]
    let users: [User]

    static func == (lhs: InnerCircleNamedList, rhs: InnerCircleNamedList) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.userIds == rhs.userIds
    }
}

/// The people you've given Inner Circle access to.
///
/// Several named lists per account — family, the gym people, work — reused by
/// every circle, place, moment and check-in set to that tier. The server keeps
/// two invariants we rely on here: only accepted connections may be on a list,
/// and access is judged against the current lists on every read, so removing
/// someone takes back what they could already see.
///
/// `userIds`/`users` are the first list, which is what the screens that
/// predate naming still edit.
struct InnerCircleList: Codable {
    let maxSize: Int
    let maxLists: Int?
    let lists: [InnerCircleNamedList]?
    let userIds: [String]
    let users: [User]

    static let empty = InnerCircleList(maxSize: 150, maxLists: 20, lists: [], userIds: [], users: [])

    /// Every list with at least one person on it: the ones worth offering as
    /// an audience, since an empty list is indistinguishable from Private.
    var usableLists: [InnerCircleNamedList] { (lists ?? []).filter { !$0.userIds.isEmpty } }
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

    // MARK: - Named lists

    func getLists(completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle/lists", method: .get, body: nil, completion: completion)
    }

    func createList(name: String, userIds: [String], completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle/lists", method: .post, body: ["name": name, "userIds": userIds], completion: completion)
    }

    func updateList(id: String, name: String? = nil, userIds: [String]? = nil,
                    completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let userIds { body["userIds"] = userIds }
        send(endpoint: "users/me/inner-circle/lists/\(id)", method: .put, body: body, completion: completion)
    }

    func deleteList(id: String, completion: @escaping (Result<InnerCircleList, Error>) -> Void) {
        send(endpoint: "users/me/inner-circle/lists/\(id)", method: .delete, body: nil, completion: completion)
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
