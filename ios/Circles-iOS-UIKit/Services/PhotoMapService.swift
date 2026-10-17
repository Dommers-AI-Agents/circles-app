import Foundation
import CoreLocation

/// One place found in the user's photos, ready for the server.
struct PhotoMapPlace {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let category: String
    let applePoiCategory: String?
    let photoUrl: String?
    /// The spot it came from, marked done once the server took it
    let spotKey: String

    var body: [String: Any] {
        var body: [String: Any] = [
            "name": name, "address": address,
            "lat": coordinate.latitude, "lng": coordinate.longitude,
            "category": category
        ]
        if let applePoiCategory { body["applePoiCategory"] = applePoiCategory }
        if let photoUrl { body["photos"] = [photoUrl] }
        return body
    }
}

struct PhotoMapBatchResult: Decodable {
    let added: Int
    let skippedDuplicates: Int?
    let circleId: String?
    /// nil on Premium
    let remainingFree: Int?
    let maxFree: Int?
    /// Some of the batch didn't fit in the free allowance
    let upgradeRequired: Bool?
}

/// POST /api/import/photos: places from photos into "Places from my photos"
/// (free up to 25, then Premium; no Google calls on the server).
enum PhotoMapService {
    enum Outcome {
        case added(PhotoMapBatchResult)
        /// The free allowance is used up
        case limitReached
        case failed(Error)
    }

    private struct Envelope: Decodable {
        let success: Bool
        let data: PhotoMapBatchResult?
    }

    static func add(_ places: [PhotoMapPlace], completion: @escaping (Outcome) -> Void) {
        APIService.shared.request(
            endpoint: "import/photos",
            method: .post,
            body: ["places": places.map(\.body)],
            requiresAuth: true
        ) { (result: Result<Envelope, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let envelope):
                    if let data = envelope.data { completion(.added(data)) } else { completion(.failed(APIError.invalidResponse)) }
                case .failure(.httpError(403, _)):
                    completion(.limitReached)
                case .failure(let error):
                    completion(.failed(error))
                }
            }
        }
    }
}
