import Foundation
import CoreLocation

/// Where Directions sends you, by name and address rather than a bare pin
/// (Wes, 2026-11-05: Maps showed coordinates, not where you're going).
struct DirectionsDestination {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D?

    /// "Fresh Monkee, 1500 S Church St, Charlotte, NC": Google Maps finds the
    /// place itself and shows it by name. Coordinates only when there's no
    /// address to give.
    var googleMapsURL: URL? {
        var components = URLComponents()
        components.scheme = "comgooglemaps"
        components.host = ""
        let label = [name, address].filter { !$0.isEmpty }.joined(separator: ", ")
        let destination: String
        if !address.isEmpty {
            destination = label
        } else if let coordinate {
            destination = "\(coordinate.latitude),\(coordinate.longitude)"
        } else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "daddr", value: destination),
                                 URLQueryItem(name: "directionsmode", value: "driving")]
        return components.url
    }
}
