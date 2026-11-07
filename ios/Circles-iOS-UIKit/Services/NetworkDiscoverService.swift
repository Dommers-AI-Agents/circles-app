import Foundation
import CoreLocation

/// Everything the My Network → Discover page shows: places your people love,
/// your month among them, and people you might know.
final class NetworkDiscoverService {
    static let shared = NetworkDiscoverService()
    private let api = APIService.shared

    struct LovedPlace: Codable, Equatable {
        struct Saver: Codable, Equatable {
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

    /// Whose places the card holds: your people's, or (nobody in your network
    /// has any yet) places people saved near you
    enum LovedScope: String, Codable { case network, community }
    struct LovedPage: Codable, Equatable {
        let scope: LovedScope
        let places: [LovedPlace]
    }
    private struct LovedEnvelope: Decodable { let success: Bool; let scope: LovedScope?; let places: [LovedPlace] }
    private struct MonthEnvelope: Decodable { let success: Bool; let data: MilestoneMonthViewController.Month }

    func lovedPlaces(completion: @escaping (Result<LovedPage, Error>) -> Void) {
        // fallback=community: a new account with no network still sees places
        // (Wes, 2026-11-07); the scope says which the server sent
        api.request(endpoint: "network/loved-places?fallback=community", method: .get) { (result: Result<LovedEnvelope, APIError>) in
            completion(result.map { LovedPage(scope: $0.scope ?? .network, places: $0.places) }.mapError { $0 as Error })
        }
    }

    func month(completion: @escaping (Result<MilestoneMonthViewController.Month, Error>) -> Void) {
        api.request(endpoint: "users/me/contributions", method: .get) { (result: Result<MonthEnvelope, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    /// Near you, follows you, people you follow but haven't connected with,
    /// and suggested — merged, each person once, under their strongest
    /// reason (same order the old Discover list used).
    func people(location: CLLocation?, completion: @escaping ([User]) -> Void) {
        let types = ["nearby", "followsYou", "following", "friendsOfFriends"]
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
