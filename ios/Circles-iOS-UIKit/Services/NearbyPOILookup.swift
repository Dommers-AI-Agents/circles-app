import MapKit

/// Businesses Apple Maps lists around a spot, nearest first. Shared by Add
/// Place's map tap and "From photos".
enum NearbyPOILookup {
    static func pointsOfInterest(near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 100,
                                 categories: [MKPointOfInterestCategory]? = nil,
                                 completion: @escaping ([MKMapItem]) -> Void) {
        pointsOfInterestResult(near: coordinate, radius: radius, categories: categories) { result in
            completion((try? result.get()) ?? [])
        }
    }

    /// Same, saying when Apple Maps failed (throttled, offline) instead of
    /// answering "nothing here". The search object is held until it answers:
    /// a released MKLocalSearch can drop its completion, which left Build my
    /// map waiting forever (Wes, 2026-10-17).
    static func pointsOfInterestResult(near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 100,
                                       categories: [MKPointOfInterestCategory]? = nil,
                                       completion: @escaping (Result<[MKMapItem], Error>) -> Void) {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        if let categories { request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories) }
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            withExtendedLifetime(search) {}
            if let error, (error as? MKError)?.code != .placemarkNotFound {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let items = (response?.mapItems ?? []).sorted {
                here.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                    < here.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
            }
            DispatchQueue.main.async { completion(.success(items)) }
        }
    }

    /// Places worth saving from a photo (PhotoPlaceKind), best first: the
    /// café, venue or park the photo was most likely of, not just the
    /// nearest storefront. Big venues may be farther (their map point sits
    /// in the middle). Up to `limit`.
    static func savablePlaces(near coordinate: CLLocationCoordinate2D, limit: Int = 6,
                              completion: @escaping ([MKMapItem]) -> Void) {
        savablePlacesResult(near: coordinate, limit: limit) { completion((try? $0.get()) ?? []) }
    }

    /// Same, with Apple Maps failures reported (Build my map retries them)
    static func savablePlacesResult(near coordinate: CLLocationCoordinate2D, limit: Int = 6,
                                    completion: @escaping (Result<[MKMapItem], Error>) -> Void) {
        // No category filter on the search: a church or venue Apple leaves
        // uncategorized would vanish; PhotoPlaceKind judges each result
        pointsOfInterestResult(near: coordinate, radius: 220) { result in
            guard case .success(let items) = result else {
                if case .failure(let error) = result { completion(.failure(error)) }
                return
            }
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let ranked = items.filter(PhotoPlaceKind.isPlace).compactMap { item -> (MKMapItem, Double)? in
                let raw = item.pointOfInterestCategory?.rawValue
                let d = here.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                                       longitude: item.placemark.coordinate.longitude))
                guard d <= PhotoPlaceKind.reach(categoryRaw: raw) else { return nil }
                return (item, PhotoPlaceKind.rankScore(distance: d, categoryRaw: raw))
            }
            completion(.success(Array(ranked.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0))))
        }
    }
}
