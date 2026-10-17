import Foundation
import MapKit

/// Which Apple Maps results found at a photo's spot are PLACES worth saving
/// (Wes, 2026-10-17): cafés, restaurants, bars, hotels, gas stations, shops,
/// venues, parks, gyms, airports, schools, hospitals, churches — never a home,
/// an apartment complex, an office or a bare street address. Pure: works on
/// the category's raw value so it's tested without MapKit lookups.
enum PhotoPlaceKind {
    private static func raw(_ names: [String]) -> Set<String> { Set(names.map { "MKPOICategory" + $0 }) }

    /// Kinds that count (Wes's list + his 2026-10-17 picks)
    static let allowed: Set<String> = raw([
        // food & drink
        "Restaurant", "Cafe", "Bakery", "Brewery", "Winery", "Distillery", "Nightlife", "FoodMarket",
        // lodging
        "Hotel", "Campground", "RVPark",
        // fuel & car
        "GasStation", "EVCharger", "CarRental", "AutomotiveRepair",
        // shops & personal care
        "Store", "Pharmacy", "Beauty", "Spa", "FitnessCenter",
        // entertainment
        "Museum", "Theater", "MovieTheater", "MusicVenue", "AmusementPark", "Aquarium", "Zoo", "Stadium",
        "Planetarium", "ConventionCenter", "Fairground", "Bowling", "MiniGolf", "GoKart",
        // sports
        "Golf", "Skating", "Skiing", "Tennis", "Baseball", "Basketball", "Soccer", "Swimming", "RockClimbing",
        "Volleyball", "Kayaking", "Surfing", "SkatePark", "Fishing",
        // outdoors & sights
        "Park", "NationalPark", "Beach", "Marina", "Hiking", "Landmark", "Castle", "Fortress", "NationalMonument",
        // travel
        "Airport", "PublicTransport",
        // civic
        "Library", "University", "School", "Hospital"
    ])

    /// Never a place to save from a photo
    static let denied: Set<String> = raw([
        "ATM", "Bank", "Parking", "Restroom", "Mailbox", "Police", "FireStation", "Laundry", "PostOffice", "AnimalService"
    ])

    /// Kinds an apartment complex or subdivision can hide behind
    /// ("Waterford At The Park" comes back as a park)
    private static let weak: Set<String> = raw(["Park", "Landmark", "NationalMonument"])

    private static let residential = try! NSRegularExpression(
        pattern: #"\b(apartments?|apts|residences?|lofts|condos?|condominiums|townhomes?|townhouses?|flats|estates|senior living|assisted living|homes|at the park|subdivision|homeowners)\b"#,
        options: [.caseInsensitive])
    /// Plainly somebody's home whatever Apple calls it ("Townhome" came back
    /// as a Hotel; Wes, 2026-10-17). Narrower than `residential`: "Residence
    /// Inn" and "Homewood Suites" are real hotels.
    private static let housing = try! NSRegularExpression(
        pattern: #"\b(apartments?|apts|townhomes?|townhouses?|condos?|condominiums|duplex|subdivision|homeowners|hoa|senior living|assisted living)\b"#,
        options: [.caseInsensitive])
    private static let notAPlace = try! NSRegularExpression(
        pattern: #"\b(parking|atm|bank|credit union|office|offices|llc|inc)\b"#, options: [.caseInsensitive])

    static func looksResidential(_ name: String) -> Bool {
        residential.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// Whether a found map item should be offered for saving.
    /// - categoryRaw: `MKPointOfInterestCategory.rawValue`, nil when Apple has none
    /// - isBareAddress: `BareAddressHeuristic.isBareAddress` for the item
    static func isPlace(name: String?, categoryRaw: String?, isBareAddress: Bool) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, !isBareAddress else { return false }
        if housing.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil { return false }
        if let category = categoryRaw {
            if denied.contains(category) { return false }
            guard allowed.contains(category) else { return false }
            return !(weak.contains(category) && looksResidential(name))
        }
        // No category from Apple: only a name that says what it is ("… Church",
        // "… Grill", "… Urgent Care"), and never a home or an office
        if looksResidential(name) { return false }
        if notAPlace.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil { return false }
        guard let mapping = AppleMapItemFormFill.mapping(forName: name) else { return false }
        return mapping.category != .finance
    }

    /// Big places whose map point can sit far from where a photo was taken
    /// (a park's middle, a stadium's entrance, a food hall's front)
    static let largeVenues: Set<String> = raw([
        "Park", "NationalPark", "Beach", "Stadium", "AmusementPark", "Zoo", "Aquarium", "Museum", "Airport", "University",
        "Hospital", "FoodMarket", "ConventionCenter", "Fairground", "Golf", "Marina", "Campground", "Landmark", "Castle"
    ])
    /// What people photograph and want on their map ahead of the small shop
    /// next door (Wes: "cafés, restaurants, bars, hotels")
    private static let favored: Set<String> = raw([
        "Restaurant", "Cafe", "Bakery", "Brewery", "Winery", "Distillery", "Nightlife", "FoodMarket", "Hotel",
        "Museum", "Theater", "MusicVenue", "Stadium", "Park", "Beach", "Zoo", "Aquarium", "AmusementPark"
    ])
    private static let minor: Set<String> = raw(["Beauty", "AutomotiveRepair", "CarRental", "EVCharger", "Pharmacy"])

    /// How far from the photo a place may be (meters)
    static func reach(categoryRaw: String?) -> Double {
        categoryRaw.map { largeVenues.contains($0) } == true ? 220 : 100
    }

    /// Lower is better: distance, minus a head start for the places people
    /// mean (a large venue's point is far by nature).
    static func rankScore(distance: Double, categoryRaw: String?) -> Double {
        guard let category = categoryRaw else { return distance + 15 }
        var score = distance
        if largeVenues.contains(category) { score -= 60 }
        if favored.contains(category) { score -= 35 }
        if minor.contains(category) { score += 30 }
        return score
    }

    /// For a live MapKit result
    static func isPlace(_ item: MKMapItem) -> Bool {
        let p = item.placemark
        let bare = BareAddressHeuristic.isBareAddress(name: item.name, hasPointOfInterestCategory: item.pointOfInterestCategory != nil,
                                                      subThoroughfare: p.subThoroughfare, thoroughfare: p.thoroughfare)
        return isPlace(name: item.name, categoryRaw: item.pointOfInterestCategory?.rawValue, isBareAddress: bare)
    }

    /// "Coffee Shop", "Restaurant", "Park" — the small label on a review row
    static func label(_ item: MKMapItem) -> String {
        let mapping = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: item.name)
        return mapping.subcategory ?? mapping.category.displayName
    }
}
