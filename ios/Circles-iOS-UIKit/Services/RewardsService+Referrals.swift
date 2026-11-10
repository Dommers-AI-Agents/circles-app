import Foundation

private struct StoreReferralsSaved: Codable { let settings: StoreReferralSettings }

extension RewardsService {

    // MARK: Owner

    func fetchReferrals(venueId: String, completion: @escaping (Result<StoreReferralsData, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/referrals", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<StoreReferralsData>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    func updateReferrals(venueId: String, settings: StoreReferralSettings, completion: @escaping (Result<StoreReferralSettings, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/referrals", method: .put, body: settings.asBody, requiresAuth: true) {
            (result: Result<RewardsEnvelope<StoreReferralsSaved>, APIError>) in
            completion(result.map(\.data.settings).mapError { $0 as Error })
        }
    }

    // MARK: The inviter on a sticker link

    private static let pendingReferrerKey = "rewards.pendingReferrer"

    /// A store link arrived with ?ref=<inviter>: kept until the scan it belongs to is sent
    func rememberReferrer(_ userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        UserDefaults.standard.set(userId, forKey: Self.pendingReferrerKey)
    }

    /// The remembered inviter, cleared on read
    func takeReferrer() -> String? {
        let value = UserDefaults.standard.string(forKey: Self.pendingReferrerKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingReferrerKey)
        return value
    }
}
