import Foundation

/// The signed-in user's daily summary.
final class DailySummaryService {
    static let shared = DailySummaryService()

    private let api: APIClient

    init(api: APIClient = APIService.shared) {
        self.api = api
    }

    // MARK: - Daily Summary
    func fetchDailySummary(completion: @escaping (Result<DailySummaryData, APIError>) -> Void) {
        api.request(
            endpoint: "users/me/daily-summary",
            method: .get,
            requiresAuth: true
        ) { (result: Result<DailySummaryResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Daily Summary Response Types
struct DailySummaryResponse: Decodable {
    let success: Bool
    let data: DailySummaryData
}

struct DailySummaryData: Decodable {
    let date: String
    let newPlaces: Int
    let newPlacesByCategory: [String: Int]
    let newConnections: Int
    let unreadMessages: Int
    let placeComments: Int
    let placeLikes: Int
    let topContributors: [DailySummaryContributor]
    let connectionCount: Int
    let userPlaceCount: Int
}

struct DailySummaryContributor: Decodable {
    let name: String
    let count: Int
}
