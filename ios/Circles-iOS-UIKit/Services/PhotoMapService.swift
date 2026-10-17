import Foundation
import MapKit
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
    /// Apple Maps' own id for the venue (iOS 18+): the server's exact
    /// duplicate check, and how the venue record learns it
    var applePlaceId: String? = nil

    var body: [String: Any] {
        var body: [String: Any] = [
            "name": name, "address": address,
            "lat": coordinate.latitude, "lng": coordinate.longitude,
            "category": category
        ]
        if let applePoiCategory { body["applePoiCategory"] = applePoiCategory }
        if let applePlaceId { body["applePlaceId"] = applePlaceId }
        if let photoUrl { body["photos"] = [photoUrl] }
        return body
    }
}

struct PhotoMapBatchResult: Decodable {
    let added: Int
    let skippedDuplicates: Int?
    let circleId: String?
    let circleName: String?
    /// nil on Premium
    let remainingFree: Int?
    let maxFree: Int?
    /// Some of the batch didn't fit in the free allowance
    let upgradeRequired: Bool?
    /// FavCoins this request earned (3, once per person, for the whole import)
    let coins: Double?
}

/// POST /api/import/photos: places from photos into "Places from my photos"
/// (free up to 25, then Premium; no Google calls on the server).
enum PhotoMapService {
    /// Where the places go
    enum Target: Equatable {
        /// "Places from my photos"
        case photos
        case circle(id: String, name: String)
        case new(name: String, privacy: PrivacyLevel, showOnMap: Bool)

        var body: [String: Any] {
            switch self {
            case .photos: return ["kind": "photos"]
            case .circle(let id, _): return ["kind": "circle", "circleId": id]
            case .new(let name, let privacy, let showOnMap):
                return ["kind": "new", "name": name, "privacy": privacy.rawValue, "showOnMap": showOnMap]
            }
        }
    }

    enum Outcome {
        case added(PhotoMapBatchResult)
        /// The free allowance is used up (or, for a new circle, the free circle cap)
        case limitReached
        case failed(Error)
    }

    private struct Envelope: Decodable {
        let success: Bool
        let data: PhotoMapBatchResult?
    }

    static func add(_ places: [PhotoMapPlace], to target: Target = .photos, completion: @escaping (Outcome) -> Void) {
        APIService.shared.request(
            endpoint: "import/photos",
            method: .post,
            body: ["places": places.map(\.body), "target": target.body],
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

extension MKMapItem {
    /// Apple Maps' stable id for this venue, when the system gives one
    /// (iOS 18+; older phones fall back to the name-and-distance check).
    var applePlaceId: String? {
        if #available(iOS 18.0, *) { return identifier?.rawValue }
        return nil
    }
}
