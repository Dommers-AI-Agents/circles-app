import Foundation
@testable import Circles_iOS

/// Records each request and answers it from a canned JSON body (decoded with
/// the app's real response decoder) or a canned error. Completes synchronously.
final class FakeAPIClient: APIClient {
    struct Call {
        let endpoint: String
        let method: RequestMethod
        let queryParams: [String: String]?
        let body: [String: Any]?
        let requiresAuth: Bool
    }

    private(set) var calls: [Call] = []
    var responseJSON: String = #"{"success": true}"#
    var error: APIError?

    func performRequest<T: Decodable>(
        endpoint: String,
        method: RequestMethod,
        queryParams: [String: String]?,
        body: [String: Any]?,
        headers: [String: String]?,
        requiresAuth: Bool,
        completion: @escaping (Result<T, APIError>) -> Void
    ) -> APIRequestHandle {
        calls.append(Call(endpoint: endpoint, method: method, queryParams: queryParams, body: body, requiresAuth: requiresAuth))
        if let error {
            completion(.failure(error))
        } else {
            do {
                let value = try APIService.makeResponseDecoder().decode(T.self, from: Data(responseJSON.utf8))
                completion(.success(value))
            } catch {
                completion(.failure(.decodingFailed(error)))
            }
        }
        return APIRequestHandle()
    }
}
