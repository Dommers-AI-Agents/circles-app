import MapKit

/// Businesses Apple Maps lists around a spot, nearest first. Shared by Add
/// Place's map tap and "From photos".
enum NearbyPOILookup {
    static func pointsOfInterest(near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 100,
                                 categories: [MKPointOfInterestCategory]? = nil,
                                 completion: @escaping ([MKMapItem]) -> Void) {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        if let categories { request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories) }
        MKLocalSearch(request: request).start { response, _ in
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let items = (response?.mapItems ?? []).sorted {
                here.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                    < here.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
            }
            DispatchQueue.main.async { completion(items) }
        }
    }

    /// Places worth saving from a photo (PhotoPlaceKind), best first: the
    /// café, venue or park the photo was most likely of, not just the
    /// nearest storefront. Big venues may be farther (their map point sits
    /// in the middle). Up to `limit`.
    static func savablePlaces(near coordinate: CLLocationCoordinate2D, limit: Int = 6,
                              completion: @escaping ([MKMapItem]) -> Void) {
        // No category filter on the search: a church or venue Apple leaves
        // uncategorized would vanish; PhotoPlaceKind judges each result
        pointsOfInterest(near: coordinate, radius: 220) { items in
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let ranked = items.filter(PhotoPlaceKind.isPlace).compactMap { item -> (MKMapItem, Double)? in
                let raw = item.pointOfInterestCategory?.rawValue
                let d = here.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                                       longitude: item.placemark.coordinate.longitude))
                guard d <= PhotoPlaceKind.reach(categoryRaw: raw) else { return nil }
                return (item, PhotoPlaceKind.rankScore(distance: d, categoryRaw: raw))
            }
            completion(ranked.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0))
        }
    }
}
