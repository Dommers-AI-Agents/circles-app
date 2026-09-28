import Foundation

/// What PATCH /rewards/venues/:id/place hands back: the canonical place record
/// after the owner's edit.
struct VenuePlaceUpdate: Codable {
    let globalPlaceId: String
    let name: String?
    let openingHours: [OpeningHour]?
}

extension RewardsService {

    /// Replaces the store's whole opening week on its place page. Free owner
    /// tier; owner-set hours survive later Google refreshes.
    func updateVenueHours(venueId: String, draft: VenueHoursDraft, completion: @escaping (Result<VenuePlaceUpdate, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "rewards/venues/\(venueId)/place",
            method: .patch,
            body: draft.requestBody,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenuePlaceUpdate>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }
}
