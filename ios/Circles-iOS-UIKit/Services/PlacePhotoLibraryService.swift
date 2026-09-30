import Foundation

/// What the viewer may do with a place's photo library.
struct PlacePhotoRights: Codable, Equatable {
    /// The venue's owner, one of its managers, or a super-user: arrange the
    /// photos, choose the cover, remove anyone's photo.
    let canManage: Bool
}

/// A place's one photo library (server: services/placePhotoService.js) —
/// arrange, set the cover, remove — and every moment posted at the place.
final class PlacePhotoLibraryService {
    static let shared = PlacePhotoLibraryService()
    private let api = APIService.shared

    struct LibraryResponse: Codable {
        let success: Bool
        let photos: [AttributedPhoto]?
        let coverPhotoUrl: String?
    }

    struct RemoveResponse: Codable {
        let success: Bool
        /// "deleted" (your own photo) or "removed" (owner/admin; stays gone)
        let mode: String?
    }

    /// New order, front first (owner/manager/super-user). Returns the library.
    func reorder(placeId: String, photoIds: [String], completion: @escaping (Result<LibraryResponse, Error>) -> Void) {
        api.request(endpoint: "places/global/\(placeId)/photos/order", method: .put,
                    body: ["photoIds": photoIds], requiresAuth: true) { (result: Result<LibraryResponse, APIError>) in
            completion(result.mapError { $0 as Error })
        }
    }

    /// Make one photo the cover — it moves to the front.
    func setCover(placeId: String, photoId: String, completion: @escaping (Result<LibraryResponse, Error>) -> Void) {
        api.request(endpoint: "places/global/\(placeId)/photos/cover", method: .put,
                    body: ["photoId": photoId], requiresAuth: true) { (result: Result<LibraryResponse, APIError>) in
            completion(result.mapError { $0 as Error })
        }
    }

    /// Delete your own photo, or (owner/admin) remove anyone's.
    func remove(placeId: String, photoId: String, completion: @escaping (Result<RemoveResponse, Error>) -> Void) {
        api.request(endpoint: "places/global/\(placeId)/media/\(photoId)", method: .delete,
                    requiresAuth: true) { (result: Result<RemoveResponse, APIError>) in
            completion(result.mapError { $0 as Error })
        }
    }

    /// Every moment at the place the viewer may see, across everyone's saves.
    func moments(placeId: String, limit: Int = 30, completion: @escaping (Result<[PlaceVideo], Error>) -> Void) {
        api.request(endpoint: "videos/reels/venue/\(placeId)", method: .get,
                    queryParams: ["limit": String(limit)], requiresAuth: true) { (result: Result<VideosResponse, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }
}
