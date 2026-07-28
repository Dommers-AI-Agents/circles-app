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
    let people: [BrowsePerson]
    let places: [CityVenue]
}

/// A person who saved a place (network view).
struct VenueSaver: Decodable {
    let id: String
    let name: String
    let profilePicture: String?
}

/// An entry in the adaptive People filter for a city.
struct BrowsePerson: Decodable {
    let id: String
    let name: String
    let profilePicture: String?
    let count: Int
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
    let rating: Double?
    let circles: [VenueCircleChip]
    let savers: [VenueSaver]
    let savedByMe: Bool

    /// A stable id for the venue (prefers the canonical global id).
    var venueId: String { globalPlaceId ?? placeId }

    /// "Added by you" / "Added by Wes" / "Added by Wes +2".
    var addedByText: String? {
        guard !savers.isEmpty else { return nil }
        if savedByMe && savers.count == 1 { return "Added by you" }
        let lead = savers.first?.name ?? "Someone"
        let extra = savers.count - 1
        return extra > 0 ? "Added by \(lead) +\(extra)" : "Added by \(lead)"
    }

    /// "★ 4.5" when a rating is present.
    var ratingText: String? {
        guard let r = rating else { return nil }
        return String(format: "★ %.1f", r)
    }

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
