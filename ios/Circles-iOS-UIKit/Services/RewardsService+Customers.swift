import Foundation

/// A store's customers, for its team (2026-11-02): who earns here, and
/// "Remove from rewards". Server: services/storeCustomers.js.
struct VenueCustomer: Codable, Equatable {
    struct Card: Codable, Equatable {
        let id: String
        let displayName: String
        let username: String?
        let profilePicture: String?
    }
    let user: Card
    /// Only for customers who shared it (claiming their first reward here)
    let email: String?
    let sharedWithStore: Bool
    let points: Int
    let purchases: Int
    let rewardsClaimed: Int
    let lastScanAt: String?
    let removed: Bool
}

struct VenueCustomersData: Codable { let customers: [VenueCustomer] }
private struct VenueCustomerRemovedData: Codable { let removed: Bool }

extension RewardsService {

    func fetchVenueCustomers(venueId: String, completion: @escaping (Result<[VenueCustomer], Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/customers", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueCustomersData>, APIError>) in
            completion(result.map(\.data.customers).mapError { $0 as Error })
        }
    }

    /// `remove` true: points here go to 0 and they stop earning; false: undo
    func setVenueCustomerRemoved(venueId: String, userId: String, remove: Bool,
                                 completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/customers/\(userId)/\(remove ? "remove" : "restore")",
                                  method: .post, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueCustomerRemovedData>, APIError>) in
            completion(result.map { _ in () }.mapError { $0 as Error })
        }
    }
}
