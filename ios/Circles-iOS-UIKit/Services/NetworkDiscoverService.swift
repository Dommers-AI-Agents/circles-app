import Foundation
import CoreLocation

/// Everything the My Network → Discover page shows: places your people love,
/// your month among them, and people you might know.
final class NetworkDiscoverService {
    static let shared = NetworkDiscoverService()
    private let api = APIService.shared

    struct LovedPlace: Decodable, Equatable {
        struct Saver: Decodable, Equatable {
            let userId: String
            let displayName: String
            let profilePicture: String?
        }
        let globalPlaceId: String
        let name: String
        let category: String?
        let address: String?
        let photo: String?
        let saverCount: Int
        let savers: [Saver]
        let viewerSaved: Bool
    }

    private struct LovedEnvelope: Decodable { let success: Bool; let places: [LovedPlace] }
    private struct MonthEnvelope: Decodable { let success: Bool; let data: MilestoneMonthViewController.Month }

    func lovedPlaces(completion: @escaping (Result<[LovedPlace], Error>) -> Void) {
        api.request(endpoint: "network/loved-places", method: .get) { (result: Result<LovedEnvelope, APIError>) in
            completion(result.map(\.places).mapError { $0 as Error })
        }
    }

    func month(completion: @escaping (Result<MilestoneMonthViewController.Month, Error>) -> Void) {
        api.request(endpoint: "users/me/contributions", method: .get) { (result: Result<MonthEnvelope, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    /// Near you, follows you and suggested, merged — each person once, under
    /// their strongest reason (same order the old Discover list used).
    func people(location: CLLocation?, completion: @escaping ([User]) -> Void) {
        let types = ["nearby", "followsYou", "friendsOfFriends"]
        var loaded: [String: [User]] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for type in types {
            group.enter()
            var endpoint = "users/contacts/discover?type=\(type)"
            if type == "nearby", let location {
                endpoint += "&lat=\(location.coordinate.latitude)&lng=\(location.coordinate.longitude)"
            }
            api.request(endpoint: endpoint, method: .get) { (result: Result<DiscoveryUsersResponse, APIError>) in
                if case .success(let response) = result {
                    lock.lock(); loaded[type] = response.users; lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(NetworkDiscoverLayout.mergePeople(types.map { loaded[$0] ?? [] }))
        }
    }
}
