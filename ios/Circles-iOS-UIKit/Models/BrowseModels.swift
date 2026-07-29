import Foundation
import CoreLocation

// Response models for the location browse lens (/api/browse/*).

struct LocationBrowseResponse: Decodable {
    let success: Bool
    let states: [BrowseStateNode]
    let unplaced: BrowseUnplaced?
}

/// A top-level region row: a US state (which drills into cities) or a whole
/// country. Non-US addresses can't be parsed to a city — the address parser only
/// knows US states — so a country carries its own `cityKey` and an empty
/// `cities`, and tapping it lists its venues directly.
struct BrowseStateNode: Decodable {
    let stateCode: String
    let state: String
    let count: Int
    let cities: [BrowseCityNode]
    let isCountry: Bool?
    let cityKey: String?

    /// True when this row has no city tier to drill into.
    var listsVenuesDirectly: Bool { isCountry == true || cities.isEmpty }

    /// The region key to pass to the city-places endpoint, when this row is a leaf.
    var directRegionKey: String? { cityKey }
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
    /// The display title — a city name, a country name, or "Unplaced".
    let city: String?
    let isCountry: Bool?
    let country: String?
    let countryCode: String?
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
