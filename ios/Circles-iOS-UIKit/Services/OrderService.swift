import Foundation

/// Order ahead (2026-10-20): the customer's calls (/orders) and the store's
/// (/rewards/venues/:id/orders, /ordering). Pay at pickup; no payments here.
final class OrderService {
    static let shared = OrderService()
    private let api = APIService.shared

    private struct Envelope<T: Decodable>: Decodable { let data: T }

    /// `pickupAt` nil = as soon as possible
    /// `test`: the store's own team trying it as a customer (marked TEST)
    func place(venueId: String, cart: OrderCart, note: String?, pickupAt: Date?, test: Bool = false,
               completion: @escaping (Result<StoreOrder, APIError>) -> Void) {
        var body: [String: Any] = ["venueId": venueId, "items": cart.requestItems,
                                   "pickup": pickupAt.map { ISO8601DateFormatter().string(from: $0) } ?? "asap"]
        if test { body["test"] = true }
        if let note, !note.isEmpty { body["note"] = note }
        api.request(endpoint: "orders", method: .post, body: body, requiresAuth: true) { (r: Result<Envelope<StoreOrder>, APIError>) in
            completion(r.map(\.data))
        }
    }

    func order(_ orderId: String, completion: @escaping (Result<StoreOrder, APIError>) -> Void) {
        api.request(endpoint: "orders/\(orderId)", method: .get, requiresAuth: true) { (r: Result<Envelope<StoreOrder>, APIError>) in
            completion(r.map(\.data))
        }
    }

    func mine(completion: @escaping (Result<[StoreOrder], APIError>) -> Void) {
        api.request(endpoint: "orders/mine", method: .get, requiresAuth: true) { (r: Result<Envelope<[StoreOrder]>, APIError>) in
            completion(r.map(\.data))
        }
    }

    /// The customer has the order in hand
    func pickedUp(_ orderId: String, completion: @escaping (Result<StoreOrder, APIError>) -> Void) {
        api.request(endpoint: "orders/\(orderId)/picked-up", method: .post, body: [:], requiresAuth: true) { (r: Result<Envelope<StoreOrder>, APIError>) in
            completion(r.map(\.data))
        }
    }

    func cancel(_ orderId: String, completion: @escaping (Result<StoreOrder, APIError>) -> Void) {
        api.request(endpoint: "orders/\(orderId)/cancel", method: .post, body: [:], requiresAuth: true) { (r: Result<Envelope<StoreOrder>, APIError>) in
            completion(r.map(\.data))
        }
    }

    // MARK: Store

    func storeOrders(venueId: String, history: Bool = false, completion: @escaping (Result<[StoreOrder], APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/orders", method: .get, queryParams: history ? ["history": "1"] : nil,
                    requiresAuth: true) { (r: Result<Envelope<[StoreOrder]>, APIError>) in
            completion(r.map(\.data))
        }
    }

    enum StoreAction: String { case accept, ready, picked_up, decline }

    func act(venueId: String, orderId: String, action: StoreAction, readyInMinutes: Int? = nil, reason: String? = nil,
             completion: @escaping (Result<StoreOrder, APIError>) -> Void) {
        var body: [String: Any] = [:]
        if let readyInMinutes { body["readyInMinutes"] = readyInMinutes }
        if let reason { body["reason"] = reason }
        api.request(endpoint: "rewards/venues/\(venueId)/orders/\(orderId)/\(action.rawValue)", method: .post, body: body,
                    requiresAuth: true) { (r: Result<Envelope<StoreOrder>, APIError>) in
            completion(r.map(\.data))
        }
    }

    /// The store's web address (order.favcircles.com/<slug>); owner only
    func setOrderSlug(venueId: String, slug: String, completion: @escaping (Result<StorefrontOrderingPage, APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/slug", method: .put, body: ["slug": slug], requiresAuth: true) { (r: Result<Envelope<StorefrontOrderingPage>, APIError>) in
            completion(r.map(\.data))
        }
    }

    func saveOrdering(venueId: String, _ ordering: StoreOrdering, completion: @escaping (Result<StoreOrdering, APIError>) -> Void) {
        let body: [String: Any] = ["enabled": ordering.enabled, "leadMinutes": ordering.leadMinutes, "note": ordering.note ?? NSNull()]
        api.request(endpoint: "rewards/venues/\(venueId)/ordering", method: .put, body: body, requiresAuth: true) { (r: Result<Envelope<StoreOrdering>, APIError>) in
            completion(r.map(\.data))
        }
    }
}
