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

    // MARK: Google Maps lists (share a whole list → one circle)

    struct GoogleListPlace {
        let name: String
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let notes: String?
        let sourceExternalId: String?
        let sourceUrl: String?

        var requestBody: [String: Any] {
            var body: [String: Any] = ["name": name]
            if let address = address { body["address"] = address }
            if let latitude = latitude, let longitude = longitude {
                body["lat"] = latitude
                body["lng"] = longitude
            }
            if let notes = notes { body["notes"] = notes }
            if let id = sourceExternalId { body["sourceExternalId"] = id }
            if let url = sourceUrl { body["sourceUrl"] = url }
            return body
        }
    }

    struct GoogleList {
        let id: String
        let name: String
        let description: String?
        let author: String?
        let url: String
        let totalCount: Int
        let truncated: Bool
        let places: [GoogleListPlace]
    }

    /// POST /import/resolve-google-list — expands a shared Google Maps LIST
    /// link into its places (server-side: Google's list endpoint is
    /// undocumented, so a breakage is a deploy, not an app release).
    /// Errors carry the HTTP status as the NSError code; 404 = NOT_A_LIST.
    func resolveGoogleList(url urlString: String,
                           completion: @escaping (Result<GoogleList, Error>) -> Void) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("import/resolve-google-list"),
                                 timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": urlString])

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var result: Result<GoogleList, Error>
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (200...299).contains(status),
               let list = json["list"] as? [String: Any],
               let id = list["id"] as? String,
               let name = list["name"] as? String {
                let places = (list["places"] as? [[String: Any]] ?? []).compactMap { dict -> GoogleListPlace? in
                    guard let placeName = dict["name"] as? String, !placeName.isEmpty else { return nil }
                    return GoogleListPlace(name: placeName,
                                           address: dict["address"] as? String,
                                           latitude: dict["lat"] as? Double,
                                           longitude: dict["lng"] as? Double,
                                           notes: dict["notes"] as? String,
                                           sourceExternalId: dict["sourceExternalId"] as? String,
                                           sourceUrl: dict["sourceUrl"] as? String)
                }
                result = .success(GoogleList(id: id,
                                             name: name,
                                             description: list["description"] as? String,
                                             author: list["author"] as? String,
                                             url: (list["url"] as? String) ?? urlString,
                                             totalCount: (list["totalCount"] as? Int) ?? places.count,
                                             truncated: (list["truncated"] as? Bool) ?? false,
                                             places: places))
            } else {
                let message = ((try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["message"] as? String)
                    ?? error?.localizedDescription ?? "Could not read that list"
                result = .failure(NSError(domain: "ShareAPIClient", code: status,
                                          userInfo: [NSLocalizedDescriptionKey: message]))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    struct ListImportResult {
        let circleId: String?
        let circleName: String
        let created: Int
        let skippedDuplicates: Int
        let failed: Int
        var upgradeRequired: Bool = false
    }

    /// POST /import/execute with source "google_list" — the whole list lands
    /// in ONE circle: `existingCircleId` if the user picked one, otherwise a
    /// new circle named after the list (server creates it). Sent in ≤300-place
    /// slices; slices after the first target the circle the first one made.
    func importGoogleList(_ list: GoogleList,
                          existingCircleId: String?,
                          completion: @escaping (Result<ListImportResult, Error>) -> Void) {
        let slices = stride(from: 0, to: max(list.places.count, 1), by: 300).map {
            Array(list.places[$0..<min($0 + 300, list.places.count)])
        }
        var aggregate = ListImportResult(circleId: existingCircleId, circleName: list.name,
                                         created: 0, skippedDuplicates: 0, failed: 0)

        func send(_ index: Int, targetCircleId: String?) {
            guard index < slices.count else {
                DispatchQueue.main.async { completion(.success(aggregate)) }
                return
            }
            var listBody: [String: Any] = [
                "name": list.name,
                "sourceUrl": list.url,
                "places": slices[index].map { $0.requestBody }
            ]
            if let description = list.description { listBody["description"] = description }
            if let targetCircleId = targetCircleId { listBody["existingCircleId"] = targetCircleId }
            let body: [String: Any] = ["source": "google_list", "lists": [listBody]]

            var request = URLRequest(url: Self.baseURL.appendingPathComponent("import/execute"),
                                     timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
                if let json = json, json["upgradeRequired"] as? Bool == true {
                    aggregate.upgradeRequired = true
                    DispatchQueue.main.async { completion(.success(aggregate)) }
                    return
                }
                guard (200...299).contains(status),
                      let json = json,
                      let first = (json["results"] as? [[String: Any]])?.first else {
                    let message = (json?["message"] as? String) ?? error?.localizedDescription ?? "Import failed"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "ShareAPIClient", code: status,
                                                    userInfo: [NSLocalizedDescriptionKey: message])))
                    }
                    return
                }
                let circleId = (first["circleId"] as? String) ?? targetCircleId
                aggregate = ListImportResult(
                    circleId: circleId,
                    circleName: (first["circleName"] as? String) ?? aggregate.circleName,
                    created: aggregate.created + ((first["created"] as? Int) ?? 0),
                    skippedDuplicates: aggregate.skippedDuplicates + ((first["skippedDuplicates"] as? Int) ?? 0),
                    failed: aggregate.failed + ((first["failed"] as? [Any])?.count ?? 0))
                send(index + 1, targetCircleId: circleId)
            }.resume()
        }
        send(0, targetCircleId: existingCircleId)
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

    /// POST /circles — create a circle inline from the share card (server
    /// defaults privacy to public, credits create_circle coins, tracks the
    /// activity — identical to an in-app create).
    func createCircle(name: String, completion: @escaping (CircleChoice?) -> Void) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("circles"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var choice: CircleChoice?
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let circle = json["circle"] as? [String: Any],
               let id = (circle["_id"] as? String) ?? (circle["id"] as? String),
               let name = circle["name"] as? String {
                choice = CircleChoice(id: id, name: name)
            }
            DispatchQueue.main.async { completion(choice) }
        }.resume()
    }

    struct SaveResult {
        let placeId: String?
        let coins: Double?
        /// True when the venue was already in the chosen circle — the server's
        /// post-enrichment duplicate gate caught it; placeId is the EXISTING
        /// save, so "View in FavCircles" still works.
        let alreadySaved: Bool
        /// True when the save hit the plan's places-per-circle limit (403
        /// upgradeRequired) — the card explains and offers the upgrade path.
        var upgradeRequired: Bool = false
        var limitCurrent: Int? = nil
        var limitMax: Int? = nil
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
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["upgradeRequired"] as? Bool == true {
                // Plan limit — an explained outcome, not an error
                result = .success(SaveResult(placeId: nil,
                                             coins: nil,
                                             alreadySaved: false,
                                             upgradeRequired: true,
                                             limitCurrent: json["currentCount"] as? Int,
                                             limitMax: json["maxAllowed"] as? Int))
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
