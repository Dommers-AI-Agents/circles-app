import Foundation

private struct MyCouponsData: Codable { let coupons: [StoreCoupon] }

extension RewardsService {

    // MARK: Customer

    /// Everything this person claimed: open ones first
    func fetchMyCoupons(completion: @escaping (Result<[StoreCoupon], Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/coupons", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<MyCouponsData>, APIError>) in
            completion(result.map(\.data.coupons).mapError { $0 as Error })
        }
    }

    /// "Use now": the coupon becomes a 15-minute counter ticket (the same
    /// ticket a points reward gets), kept as the active voucher
    func useCoupon(claimId: String, completion: @escaping (Result<StoreCouponTicket, Error>) -> Void) {
        APIService.shared.attestedRequest(endpoint: "rewards/coupons/\(claimId)/use", method: .post, body: [:]) {
            (result: Result<RewardsEnvelope<StoreCouponTicket>, APIError>) in
            if case .success(let response) = result { self.storeActiveVoucher(response.data.voucher) }
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    // MARK: The coupon on a sticker link

    private static let pendingCouponKey = "rewards.pendingCoupon"

    /// A store link arrived with ?c=<coupon>: kept until the scan it belongs to is sent
    func rememberCoupon(_ couponId: String?) {
        guard let couponId, !couponId.isEmpty else { return }
        UserDefaults.standard.set(couponId, forKey: Self.pendingCouponKey)
    }

    /// The remembered coupon, cleared on read
    func takeCoupon() -> String? {
        let value = UserDefaults.standard.string(forKey: Self.pendingCouponKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingCouponKey)
        return value
    }

    // MARK: Owner

    func fetchCoupons(venueId: String, completion: @escaping (Result<[VenueCoupon], Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/coupons", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueCouponsData>, APIError>) in
            completion(result.map(\.data.coupons).mapError { $0 as Error })
        }
    }

    func createCoupon(venueId: String, draft: VenueCouponEdit, completion: @escaping (Result<VenueCouponSaved, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/coupons", method: .post, body: draft.asBody, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueCouponSaved>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func updateCoupon(venueId: String, couponId: String, body: [String: Any], completion: @escaping (Result<VenueCouponSaved, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/coupons/\(couponId)", method: .put, body: body, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueCouponSaved>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func deleteCoupon(venueId: String, couponId: String, completion: @escaping (Result<[VenueCoupon], Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/coupons/\(couponId)", method: .delete, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueCouponsData>, APIError>) in
            completion(result.map(\.data.coupons).mapError { $0 as Error })
        }
    }
}
