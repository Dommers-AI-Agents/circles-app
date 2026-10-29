import Foundation

/// Check-in endpoints (create, active, respond, end, at a place).
final class CheckInService {
    static let shared = CheckInService()

    private let api: APIClient

    init(api: APIClient = APIService.shared) {
        self.api = api
    }

    // MARK: - Check-In API
    
    /// `offersRatingAfterward`: false when the check-in screen already asked
    /// "How was it?" — the one-screen composer does, so asking again once it
    /// closes was a second prompt for the same visit.
    func createCheckIn(_ checkInData: [String: Any], offersRatingAfterward: Bool = true, completion: @escaping (Result<(checkIn: CheckIn, stats: CheckInStats?), APIError>) -> Void) {
        api.request(
            endpoint: "check-ins",
            method: .post,
            body: checkInData,
            requiresAuth: true
        ) { (result: Result<APIResponse<CheckIn>, APIError>) in
            switch result {
            case .success(let response):
                // A check-in earns a coin (once per venue per day)
                PiggyBankDepositView.play(credit: response.piggyBank)
                var info: [String: Any] = ["checkInId": response.data.id, "placeName": response.data.placeName]
                if let placeId = response.data.placeId { info["placeId"] = placeId }
                if let stats = response.myCheckInStats { info["stats"] = stats }
                // On main: observers touch labels and layout constraints, and
                // this completion arrives on URLSession's queue.
                NotificationCenter.default.postOnMain(name: .checkInCreated, userInfo: info)
                // "How was it this time?" — once the check-in flow is off screen,
                // and only if that flow didn't already ask
                if offersRatingAfterward, let placeId = response.data.placeId {
                    PostCheckInRatePresenter.offer(placeId: placeId, checkInId: response.data.id, placeName: response.data.placeName)
                }
                completion(.success((checkIn: response.data, stats: response.myCheckInStats)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getActiveCheckIns(completion: @escaping (Result<[CheckIn], APIError>) -> Void) {
        api.request(
            endpoint: "check-ins/active",
            method: .get,
            requiresAuth: true
        ) { (result: Result<APIResponse<[CheckIn]>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getMyActiveCheckIns(completion: @escaping (Result<[CheckIn], APIError>) -> Void) {
        api.request(
            endpoint: "check-ins/my-active",
            method: .get,
            requiresAuth: true
        ) { (result: Result<APIResponse<[CheckIn]>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func respondToCheckIn(checkInId: String, status: String, completion: @escaping (Result<CheckIn, APIError>) -> Void) {
        api.request(
            endpoint: "check-ins/\(checkInId)/respond",
            method: .put,
            body: ["status": status],
            requiresAuth: true
        ) { (result: Result<APIResponse<CheckIn>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func endCheckIn(checkInId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(
            endpoint: "check-ins/\(checkInId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getCheckInsAtPlace(placeId: String, completion: @escaping (Result<[CheckIn], APIError>) -> Void) {
        api.request(
            endpoint: "check-ins/at-place/\(placeId)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<APIResponse<[CheckIn]>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
