import Foundation

/// The signed-in user's own history for Profile › Activity.
final class ProfileActivityService {
    static let shared = ProfileActivityService()

    func fetchPage(filter: ProfileActivityTimeline.Filter, cursor: String?, limit: Int = 30,
                   completion: @escaping (Result<OwnActivityPage, APIError>) -> Void) {
        var endpoint = "users/me/activity?filter=\(filter.rawValue)&limit=\(limit)"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "&cursor=\(encoded)"
        }
        APIService.shared.request(endpoint: endpoint, method: .get, requiresAuth: true) { (result: Result<OwnActivityPage, APIError>) in
            DispatchQueue.main.async { completion(result) }
        }
    }

    func fetchSummary(month: String? = nil, completion: @escaping (Result<OwnActivitySummary, APIError>) -> Void) {
        let zone = TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "UTC"
        var endpoint = "users/me/activity/summary?timezone=\(zone)"
        if let month { endpoint += "&month=\(month)" }
        APIService.shared.request(endpoint: endpoint, method: .get, requiresAuth: true) { (result: Result<OwnActivitySummaryResponse, APIError>) in
            DispatchQueue.main.async { completion(result.map(\.summary)) }
        }
    }
}
