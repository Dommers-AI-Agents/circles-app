import Foundation

/// Location browse lens over the user's saved places (State › City › venues).
/// Backed by /api/browse/* — a derived view; it never modifies circles.
final class BrowseService {
    static let shared = BrowseService()
    private init() {}

    /// Full State → City tree with pin counts (+ optional Unplaced bucket).
    func getLocations(completion: @escaping (Result<LocationBrowseResponse, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "browse/locations",
            method: .get,
            requiresAuth: true
        ) { (result: Result<LocationBrowseResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Every venue in a city across all the user's circles (source-circle chips).
    func getCityPlaces(cityKey: String, completion: @escaping (Result<CityPlacesResponse, Error>) -> Void) {
        let encoded = cityKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cityKey
        APIService.shared.request(
            endpoint: "browse/cities/\(encoded)/places",
            method: .get,
            requiresAuth: true
        ) { (result: Result<CityPlacesResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response))
            case .failure(let error): completion(.failure(error))
            }
        }
    }
}
