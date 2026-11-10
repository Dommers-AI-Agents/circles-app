import MapKit

/// The businesses around a visit, as `VisitPlaceSuggestion` candidates.
enum VisitPlaceSuggester {
    static func candidates(latitude: Double, longitude: Double,
                           completion: @escaping ([VisitPlaceSuggestion.Candidate]) -> Void) {
        candidatesResult(latitude: latitude, longitude: longitude) { completion((try? $0.get()) ?? []) }
    }

    /// Same, saying when Apple Maps failed (cut off in the background,
    /// throttled, offline) instead of answering "nothing here", so the visit
    /// is looked up again later rather than left as an address.
    static func candidatesResult(latitude: Double, longitude: Double,
                                 completion: @escaping (Result<[VisitPlaceSuggestion.Candidate], Error>) -> Void) {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let here = CLLocation(latitude: latitude, longitude: longitude)
        NearbyPOILookup.pointsOfInterestResult(near: center, radius: VisitPlaceSuggestion.searchRadius) { result in
            completion(result.map { items in
                items.compactMap { item in
                    guard let name = item.name, !name.isEmpty else { return nil }
                    let coordinate = item.placemark.coordinate
                    let mapped = item.pointOfInterestCategory.flatMap { AppleMapItemFormFill.mapping(forPOICategory: $0) }
                    return VisitPlaceSuggestion.Candidate(
                        name: name,
                        address: Self.address(of: item.placemark),
                        category: mapped?.category.rawValue,
                        distance: here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)))
                }
            })
        }
    }

    private static func address(of p: MKPlacemark) -> String {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
