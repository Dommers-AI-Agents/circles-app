import MapKit

/// Businesses Apple Maps lists around a spot, nearest first. Shared by Add
/// Place's map tap and "From photos".
enum NearbyPOILookup {
    static func pointsOfInterest(near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 100,
                                 completion: @escaping ([MKMapItem]) -> Void) {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        MKLocalSearch(request: request).start { response, _ in
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let items = (response?.mapItems ?? []).sorted {
                here.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                    < here.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
            }
            DispatchQueue.main.async { completion(items) }
        }
    }
}
