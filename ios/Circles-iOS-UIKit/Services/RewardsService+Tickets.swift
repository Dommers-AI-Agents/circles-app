import Foundation

/// Reward tickets (2026-11-01): a redeemed offer is a 15-minute ticket the
/// customer shows at the counter; staff tap "Given" on it, or it expires
/// and the points come back.
struct RewardTicketsData: Codable {
    let active: [RewardVoucher]
    let recent: [RewardVoucher]
}

/// A ticket on the store team's "Rewards used" list
struct VenueRewardTicket: Codable {
    let voucherId: String
    let offerTitle: String
    let pointsCost: Int
    let voucherCode: String
    let createdAt: String
    let status: String
    let givenAt: String?
    let customerName: String
}

private struct VenueRewardTicketsData: Codable { let vouchers: [VenueRewardTicket] }

extension RewardsService {

    func fetchRewardTickets(completion: @escaping (Result<RewardTicketsData, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/vouchers", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<RewardTicketsData>, APIError>) in
            if case .success(let response) = result {
                // The server refunds expired tickets on this read
                if response.data.recent.contains(where: { $0.status == "expired" }) { RewardsService.postBalanceChanged() }
                if let open = response.data.active.first { self.storeActiveVoucher(open) } else { self.clearActiveVoucher() }
            }
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    /// Staff tapped "Given" on the customer's phone
    func markRewardGiven(_ voucher: RewardVoucher, completion: @escaping (Result<RewardVoucher, Error>) -> Void) {
        guard let voucherId = voucher.voucherId else {
            clearActiveVoucher()
            var given = voucher
            given.status = "given"
            return completion(.success(given))
        }
        APIService.shared.attestedRequest(endpoint: "rewards/vouchers/\(voucherId)/given", method: .post, body: [:]) {
            (result: Result<RewardsEnvelope<RewardVoucher>, APIError>) in
            if case .success = result { self.clearActiveVoucher() }
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func fetchVenueRewardTickets(venueId: String, completion: @escaping (Result<[VenueRewardTicket], Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/vouchers", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueRewardTicketsData>, APIError>) in
            completion(result.map(\.data.vouchers).mapError { $0 as Error })
        }
    }

    /// The open ticket at this store, if any (from the last redeem or fetch)
    func activeTicket(venueId: String?, venueName: String?) -> RewardVoucher? {
        guard let ticket = getActiveVoucher(), ticket.status != "given" else { return nil }
        if let venueId, let ticketVenue = ticket.venueId { return ticketVenue == venueId ? ticket : nil }
        return ticket.venueName == venueName ? ticket : nil
    }
}
