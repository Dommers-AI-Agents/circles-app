import Foundation

/// The server's "you already saved this place" answer to a save
/// (400 `DUPLICATE_PLACE`), which replaced Add Place downloading every
/// circle's places before it would save.
struct PlaceDuplicate: Equatable {
    let placeId: String
    let placeName: String?
    let circleId: String?
    let circleName: String?

    /// "You already have Atlantic Club in your "Gym" circle. What would you like to do?"
    var message: String {
        let place = placeName.map { "\"\($0)\"" } ?? "this place"
        if let circleName { return "You already have \(place) in your \"\(circleName)\" circle. What would you like to do?" }
        return "You already saved \(place). What would you like to do?"
    }

    /// nil unless the error is that answer.
    static func from(_ error: Error) -> PlaceDuplicate? {
        guard let apiError = error as? APIError, case .httpError(_, let data) = apiError, let data else { return nil }
        return from(json: data)
    }

    static func from(json data: Data) -> PlaceDuplicate? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["code"] as? String == "DUPLICATE_PLACE",
              let placeId = body["existingPlaceId"] as? String, !placeId.isEmpty else { return nil }
        return PlaceDuplicate(placeId: placeId,
                              placeName: body["existingPlaceName"] as? String,
                              circleId: body["existingCircleId"] as? String,
                              circleName: body["existingCircleName"] as? String)
    }
}
