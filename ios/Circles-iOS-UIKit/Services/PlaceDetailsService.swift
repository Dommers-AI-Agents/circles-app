import Foundation

/// GET /places/global/:id → detailRights: may this viewer change the shared details?
struct PlaceDetailRights: Codable, Equatable {
    let canEdit: Bool
}

/// What PATCH /places/global/:id/details hands back: the place's shared
/// details after the change.
struct PlaceDetailsUpdate: Codable {
    let globalPlaceId: String
    let name: String?
    let address: String?
    let category: String?
    let description: String?
    let phone: String?
    let website: String?
    let openingHours: [OpeningHour]?
}

/// The one way the app changes a place's shared details — name, address and
/// location, category, description, phone, website, hours — the parts every
/// saver sees. The server allows the store's owner/managers and admins only,
/// writes the place record once and copies it to every save.
///
/// Personal fields (notes, privacy, tags, circle, rating) are NOT here: they
/// belong to each person's own save (PlaceService.updatePlace).
final class PlaceDetailsService {
    static let shared = PlaceDetailsService()
    private init() {}

    /// - Parameters:
    ///   - placeId: the place record's id (a save id also works; the server resolves it)
    ///   - fields: only what changed — see PlaceEditPlan.detailChanges
    func update(placeId: String, fields: [String: Any], completion: @escaping (Result<PlaceDetailsUpdate, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/global/\(placeId)/details",
            method: .patch,
            body: fields,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<PlaceDetailsUpdate>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }
}
