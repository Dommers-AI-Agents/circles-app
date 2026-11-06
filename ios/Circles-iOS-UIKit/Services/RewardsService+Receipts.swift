import Foundation

/// Points for delivery orders (2026-11-06): the customer sends a receipt;
/// the store's team answers, or it pays right away (Automatic).
struct ReceiptSubmitResult: Codable, Equatable {
    let claimId: String
    /// "approved" (points now) or "pending" (the team decides)
    let status: String
    let points: Int?
    let venueBalance: Int?
}

struct VenueReceipt: Codable, Equatable {
    struct Checks: Codable, Equatable {
        let storeName: Bool
        let date: Bool
        let orderNumber: Bool
    }
    struct Reading: Codable, Equatable {
        let storeLine: String?
        let orderDate: String?
        let orderNumber: String?
        let deliveryApp: String?
        let total: String?
    }
    let claimId: String
    let status: String
    let createdAt: String?
    let checks: Checks?
    let receipt: Reading?
    let user: StoreFeedbackEntry.Card?
    let imageUrl: String?
}

struct VenueReceiptList: Codable {
    let receipts: [VenueReceipt]
    let mode: String
}

struct ReceiptApproveResult: Codable { let approved: Bool; let points: Int?; let alreadyEarned: Bool? }
struct ReceiptDeclineResult: Codable { let declined: Bool }
struct ReceiptModeResult: Codable { let deliveryReceipts: String }

/// The store's setting, as the owner reads it
enum DeliveryReceiptMode: String, CaseIterable {
    case off, approve, auto

    var title: String {
        switch self {
        case .off: return "Off"
        case .approve: return "I approve each one"
        case .auto: return "Automatic"
        }
    }
}

extension RewardsService {

    func sendReceipt(venueId: String, imageBase64: String, reading: ReceiptReading,
                     completion: @escaping (Result<ReceiptSubmitResult, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/receipts", method: .post,
                                  body: ["image": imageBase64, "receipt": reading.body], requiresAuth: true) {
            (result: Result<RewardsEnvelope<ReceiptSubmitResult>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func fetchVenueReceipts(venueId: String, completion: @escaping (Result<VenueReceiptList, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/receipts", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueReceiptList>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func approveReceipt(venueId: String, claimId: String, completion: @escaping (Result<ReceiptApproveResult, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/receipts/\(claimId)/approve", method: .post,
                                  body: [:], requiresAuth: true) {
            (result: Result<RewardsEnvelope<ReceiptApproveResult>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func declineReceipt(venueId: String, claimId: String, completion: @escaping (Result<ReceiptDeclineResult, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/receipts/\(claimId)/decline", method: .post,
                                  body: [:], requiresAuth: true) {
            (result: Result<RewardsEnvelope<ReceiptDeclineResult>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func setDeliveryReceiptMode(venueId: String, mode: DeliveryReceiptMode, completion: @escaping (Result<ReceiptModeResult, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/delivery-receipts", method: .put,
                                  body: ["mode": mode.rawValue], requiresAuth: true) {
            (result: Result<RewardsEnvelope<ReceiptModeResult>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }
}
