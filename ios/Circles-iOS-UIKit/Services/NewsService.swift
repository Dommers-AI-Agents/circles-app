import Foundation

/// News tab API: the source catalog (+ the user's enabled sources) and the
/// merged headline feed. The feed call sends no source list — the backend
/// reads the user's stored preference, so client and server can't drift.
class NewsService {
    static let shared = NewsService()

    private let apiService = APIService.shared

    private init() {}

    func fetchSources(completion: @escaping (Result<NewsSourcesResponse, Error>) -> Void) {
        apiService.request(
            endpoint: "news/sources",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<NewsSourcesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchFeed(completion: @escaping (Result<NewsFeedResponse, Error>) -> Void) {
        apiService.request(
            endpoint: "news/feed",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<NewsFeedResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
