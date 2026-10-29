import Foundation

/// The one call services make to the backend. `APIService` is the real one;
/// tests hand a service a fake so its decoding and endpoint building can be
/// checked without a network.
///
/// Services hold an `api: APIClient` (default `APIService.shared`) and call
/// `api.request(...)` exactly as they would call `APIService.shared.request`.
protocol APIClient: AnyObject {
    /// Every parameter spelled out; callers use the defaulted `request` below.
    func performRequest<T: Decodable>(
        endpoint: String,
        method: RequestMethod,
        queryParams: [String: String]?,
        body: [String: Any]?,
        headers: [String: String]?,
        requiresAuth: Bool,
        completion: @escaping (Result<T, APIError>) -> Void
    ) -> APIRequestHandle
}

extension APIClient {
    /// Same signature and defaults as `APIService.request`.
    @discardableResult
    func request<T: Decodable>(
        endpoint: String,
        method: RequestMethod = .get,
        queryParams: [String: String]? = nil,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true,
        completion: @escaping (Result<T, APIError>) -> Void
    ) -> APIRequestHandle {
        performRequest(endpoint: endpoint, method: method, queryParams: queryParams, body: body,
                       headers: headers, requiresAuth: requiresAuth, completion: completion)
    }
}

extension APIService: APIClient {
    func performRequest<T: Decodable>(
        endpoint: String,
        method: RequestMethod,
        queryParams: [String: String]?,
        body: [String: Any]?,
        headers: [String: String]?,
        requiresAuth: Bool,
        completion: @escaping (Result<T, APIError>) -> Void
    ) -> APIRequestHandle {
        // Resolves to APIService's own `request` (a class method wins over
        // the protocol extension's).
        request(endpoint: endpoint, method: method, queryParams: queryParams, body: body,
                headers: headers, requiresAuth: requiresAuth, completion: completion)
    }
}
