import Foundation

class ActivityService {
    
    // MARK: - Singleton
    static let shared = ActivityService()
    
    private init() {}
    
    // MARK: - Activity Methods
    
    /// Fetch network activities
    func getNetworkActivities(limit: Int = 20, offset: Int = 0, since: Date? = nil, completion: @escaping (Result<ActivityResponse, Error>) -> Void) {
        var queryParams: [String: String] = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        
        if let since = since {
            let formatter = ISO8601DateFormatter()
            queryParams["since"] = formatter.string(from: since)
        }
        
        Logger.debug("🔍 ActivityService: Fetching network activities with params: \(queryParams)")
        
        APIService.shared.request(
            endpoint: "network/activities",
            method: .get,
            queryParams: queryParams
        ) { (result: Result<ActivityResponse, APIError>) in
            switch result {
            case .success(let response):
                Logger.debug("✅ ActivityService: Received \(response.activities.count) activities")
                Logger.debug("📊 ActivityService: Response - success: \(response.success), count: \(response.count), hasMore: \(response.hasMore)")
                if !response.activities.isEmpty {
                    Logger.debug("🎯 ActivityService: First activity type: \(response.activities[0].type.rawValue)")
                    Logger.debug("🎯 ActivityService: First activity actor: \(response.activities[0].actor?.displayName ?? "Unknown")")
                }
                completion(.success(response))
            case .failure(let error):
                Logger.debug("❌ ActivityService: Error fetching activities: \(error)")
                Logger.debug("🔍 ActivityService: Error details - \(error.localizedDescription)")
                if case .httpError(let statusCode, let data) = error {
                    Logger.debug("🔍 ActivityService: HTTP \(statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        Logger.debug("🔍 ActivityService: Error response: \(errorString)")
                    }
                }
                completion(.failure(error))
            }
        }
    }
    
    /// Mark activities as read
    func markActivitiesAsRead(activityIds: [String], completion: @escaping (Result<Bool, Error>) -> Void) {
        let body = ["activityIds": activityIds]
        
        APIService.shared.request(
            endpoint: "network/activities/mark-read",
            method: .put,
            body: body
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                Logger.debug("❌ Error marking activities as read: \(error)")
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Response Models

struct ActivityResponse: Codable {
    let success: Bool
    let activities: [Activity]
    let count: Int
    let hasMore: Bool
}