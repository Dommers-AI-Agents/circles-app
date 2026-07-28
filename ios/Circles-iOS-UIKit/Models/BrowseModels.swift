import Foundation
import CoreLocation

// Response models for the location browse lens (/api/browse/*).

struct LocationBrowseResponse: Decodable {
    let success: Bool
    let states: [BrowseStateNode]
    let unplaced: BrowseUnplaced?
}

struct BrowseStateNode: Decodable {
    let stateCode: String
    let state: String
    let count: Int
    let cities: [BrowseCityNode]
}

struct BrowseCityNode: Decodable {
    let city: String
    let cityKey: String
    let count: Int
}

struct BrowseUnplaced: Decodable {
    let cityKey: String
    let count: Int
}

struct CityPlacesResponse: Decodable {
    let success: Bool
    let cityKey: String
    let city: String?
    let state: String?
    let stateCode: String?
    let count: Int
    let topNeighborhood: TopNeighborhood?
    let places: [CityVenue]
}

struct TopNeighborhood: Decodable {
    let neighborhood: String
    let count: Int
}

struct VenueCircleChip: Decodable {
    let id: String
    let name: String
}

struct CityVenue: Decodable {
    let globalPlaceId: String?
    let placeId: String
    let name: String
    let category: String
    let address: String
    let neighborhood: String?
    let city: String?
    let state: String?
    let stateCode: String?
    let location: GeoLocation?
    let circles: [VenueCircleChip]

    /// A stable id for the venue (prefers the canonical global id).
    var venueId: String { globalPlaceId ?? placeId }

    var coordinate: CLLocationCoordinate2D? {
        guard let coords = location?.coordinates, coords.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
    }

    /// Subtitle like "Café · South End" (category, then neighborhood if present).
    var subtitle: String {
        let cat = PlaceCategory(rawValue: category)?.displayName ?? category.capitalized
        if let n = neighborhood, !n.isEmpty { return "\(cat) · \(n)" }
        return cat
    }
}
