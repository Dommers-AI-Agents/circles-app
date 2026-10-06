import MapKit

/// The businesses around a visit, as `VisitPlaceSuggestion` candidates.
enum VisitPlaceSuggester {
    static func candidates(latitude: Double, longitude: Double,
                           completion: @escaping ([VisitPlaceSuggestion.Candidate]) -> Void) {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let here = CLLocation(latitude: latitude, longitude: longitude)
        NearbyPOILookup.pointsOfInterest(near: center, radius: VisitPlaceSuggestion.searchRadius) { items in
            let candidates: [VisitPlaceSuggestion.Candidate] = items.compactMap { item in
                guard let name = item.name, !name.isEmpty else { return nil }
                let coordinate = item.placemark.coordinate
                let mapped = item.pointOfInterestCategory.flatMap { AppleMapItemFormFill.mapping(forPOICategory: $0) }
                return .init(name: name,
                             address: Self.address(of: item.placemark),
                             category: mapped?.category.rawValue,
                             distance: here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)))
            }
            completion(candidates)
        }
    }

    private static func address(of p: MKPlacemark) -> String {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
