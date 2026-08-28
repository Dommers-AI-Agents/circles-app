import Foundation

/// Minimal API client for the Share Extension — reads the session token from
/// the App Group auth mirror (ExtensionAuthMailbox) and talks to the two
/// endpoints the share flow needs. Deliberately NOT the app's APIService:
/// extensions want a tiny footprint and no app-wide singletons.
struct ShareAPIClient {

    static let baseURL = URL(string: "https://circles-backend-196924649787.us-central1.run.app/api")!

    let authToken: String

    /// Nil when the app has never mirrored a session (not logged in).
    static func fromMailbox() -> ShareAPIClient? {
        guard let payload = ExtensionAuthMailbox.read() else { return nil }
        if let expirationString = payload.tokenExpiration,
           let expiration = ISO8601DateFormatter().date(from: expirationString),
           expiration <= Date() {
            return nil
        }
        return ShareAPIClient(authToken: payload.authToken)
    }

    struct CircleChoice {
        let id: String
        let name: String
    }

    /// GET /circles/me → the user's circles, for the picker.
    func getCircles(completion: @escaping ([CircleChoice]) -> Void) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("circles/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var choices: [CircleChoice] = []
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let circles = json["circles"] as? [[String: Any]] {
                choices = circles.compactMap { dict in
                    guard let id = (dict["_id"] as? String) ?? (dict["id"] as? String),
                          let name = dict["name"] as? String else { return nil }
                    return CircleChoice(id: id, name: name)
                }
            }
            DispatchQueue.main.async { completion(choices) }
        }.resume()
    }

    struct KnownVenue {
        let photoURL: String?
        let description: String?
    }

    /// GET /places/global/match — does the platform already know this venue?
    /// Powers the card's photo + description preview before saving.
    func matchKnownVenue(name: String,
                         latitude: Double,
                         longitude: Double,
                         completion: @escaping (KnownVenue?) -> Void) {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("places/global/match"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var venue: KnownVenue?
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let match = (json["data"] as? [String: Any])?["match"] as? [String: Any] {
                venue = KnownVenue(
                    photoURL: (match["photos"] as? [String])?.first,
                    description: match["description"] as? String
                )
            }
            DispatchQueue.main.async { completion(venue) }
        }.resume()
    }

    struct SaveResult {
        let placeId: String?
        let coins: Double?
        /// True when the venue was already in the chosen circle — the server's
        /// post-enrichment duplicate gate caught it; placeId is the EXISTING
        /// save, so "View in FavCircles" still works.
        let alreadySaved: Bool
    }

    /// POST /places — the normal create path, so globalPlaceId stamping and
    /// FavCoin credit happen server-side exactly as an in-app add would.
    func createPlace(name: String,
                     address: String,
                     latitude: Double,
                     longitude: Double,
                     category: String,
                     circleId: String,
                     completion: @escaping (Result<SaveResult, Error>) -> Void) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("places"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "address": address,
            "category": category,
            "circleId": circleId,
            // GeoJSON order: [lng, lat]
            "location": ["type": "Point", "coordinates": [longitude, latitude]],
            // The extension can't run the Places SDK — the backend enriches
            // (canonical venue first, Google only for platform-new venues)
            "enrichFromGoogle": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<SaveResult, Error>
            if let error = error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                var coins: Double?
                var placeId: String?
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let piggy = json["piggyBank"] as? [String: Any],
                       piggy["credited"] as? Bool == true {
                        coins = piggy["coins"] as? Double
                    }
                    if let place = json["place"] as? [String: Any] {
                        placeId = (place["_id"] as? String) ?? (place["id"] as? String)
                    }
                }
                result = .success(SaveResult(placeId: placeId, coins: coins, alreadySaved: false))
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["code"] as? String == "DUPLICATE_PLACE" {
                // Not a failure — the place is already in that circle
                result = .success(SaveResult(placeId: json["existingPlaceId"] as? String,
                                             coins: nil,
                                             alreadySaved: true))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                result = .failure(NSError(
                    domain: "ShareAPIClient", code: status,
                    userInfo: [NSLocalizedDescriptionKey: "Save failed (\(status))"]))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
