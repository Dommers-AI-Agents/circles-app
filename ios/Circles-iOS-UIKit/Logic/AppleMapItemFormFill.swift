import Foundation
import MapKit

/// The pure part of filling the add-place form from an Apple Maps result:
/// residential detection, category + subcategory from the POI category (or
/// the name when Apple gives none), and the synthesized description. The
/// form writes, distance line, pin and asset fetch stay on the controller.
enum AppleMapItemFormFill {
    struct CategoryMapping: Equatable {
        let category: PlaceCategory
        let subcategory: String?
        init(_ category: PlaceCategory, _ subcategory: String? = nil) {
            self.category = category
            self.subcategory = subcategory
        }
    }

    /// An address entity has no business name; the user names it themselves.
    static func isResidentialAddress(name: String?) -> Bool {
        name == nil || name?.isEmpty == true
    }

    /// Apple's POI category first; when Apple has none, or one we don't map,
    /// the business name decides (Apple has no clinic/dentist/gym-studio
    /// categories, so "Atrium Health Urgent Care" arrives with no POI
    /// category at all). Only when both draw a blank is it "Other" — the map
    /// pin icon comes from this, so a real category matters.
    static func categoryMapping(poiCategory: MKPointOfInterestCategory?, name: String?) -> CategoryMapping {
        if let poiCategory = poiCategory, let mapped = mapping(forPOICategory: poiCategory) {
            return mapped
        }
        return mapping(forName: name) ?? CategoryMapping(.other)
    }

    /// nil = a POI category we have no mapping for.
    static func mapping(forPOICategory poiCategory: MKPointOfInterestCategory) -> CategoryMapping? {
        switch poiCategory {
        case .restaurant: return CategoryMapping(.restaurant)
        case .cafe: return CategoryMapping(.cafe, "Coffee Shop")
        case .bakery: return CategoryMapping(.cafe, "Bakery")
        case .nightlife: return CategoryMapping(.bar, "Nightclub")
        case .brewery: return CategoryMapping(.bar, "Brewery")
        case .winery: return CategoryMapping(.bar, "Wine Bar")
        case .hotel, .campground: return CategoryMapping(.hotel)
        case .store: return CategoryMapping(.retail)
        case .foodMarket: return CategoryMapping(.retail, "Grocery Store")
        case .gasStation, .evCharger, .carRental, .laundry, .postOffice: return CategoryMapping(.service)
        case .bank, .atm: return CategoryMapping(.finance)
        case .pharmacy: return CategoryMapping(.healthcare, "Pharmacy")
        case .hospital: return CategoryMapping(.healthcare, "Hospital")
        case .fitnessCenter: return CategoryMapping(.fitness, "Gym")
        case .parking: return CategoryMapping(.transport, "Parking")
        case .airport: return CategoryMapping(.transport, "Airport")
        case .fireStation, .police: return CategoryMapping(.service)
        case .publicTransport: return CategoryMapping(.transport)
        case .school, .university, .library: return CategoryMapping(.education)
        case .movieTheater: return CategoryMapping(.entertainment, "Movie Theater")
        case .museum: return CategoryMapping(.attraction, "Museum")
        case .park: return CategoryMapping(.outdoor, "Park")
        case .beach: return CategoryMapping(.outdoor, "Beach")
        case .nationalPark: return CategoryMapping(.outdoor)
        case .theater: return CategoryMapping(.entertainment, "Theater")
        case .zoo: return CategoryMapping(.attraction, "Zoo")
        case .aquarium: return CategoryMapping(.attraction, "Aquarium")
        case .amusementPark: return CategoryMapping(.attraction, "Theme Park")
        case .stadium: return CategoryMapping(.entertainment)
        case .marina: return CategoryMapping(.outdoor)
        default:
            if #available(iOS 18.0, *) {
                switch poiCategory {
                case .distillery: return CategoryMapping(.bar, "Distillery")
                case .spa: return CategoryMapping(.service, "Spa")
                case .beauty: return CategoryMapping(.service, "Beauty Salon")
                case .automotiveRepair, .animalService, .mailbox: return CategoryMapping(.service)
                case .rvPark: return CategoryMapping(.hotel)
                case .musicVenue: return CategoryMapping(.entertainment, "Music Venue")
                case .bowling, .miniGolf, .goKart, .fairground, .conventionCenter: return CategoryMapping(.entertainment)
                case .castle, .landmark, .fortress, .nationalMonument: return CategoryMapping(.attraction, "Landmark")
                case .planetarium: return CategoryMapping(.attraction)
                case .golf, .tennis, .swimming, .rockClimbing, .skating, .baseball, .basketball, .soccer, .volleyball:
                    return CategoryMapping(.fitness)
                case .hiking, .kayaking, .fishing, .surfing, .skiing, .skatePark: return CategoryMapping(.outdoor)
                default: return nil
                }
            }
            return nil
        }
    }

    /// Name keywords → category, first match wins; more specific first so
    /// "Urgent Care Pharmacy" is healthcare before "Pub Burger" is a bar.
    /// Whole words only: "barber" is not a bar, "Finnegan's" is not an inn.
    private static let nameRules: [(pattern: NSRegularExpression, mapping: CategoryMapping)] = [
        (#"\b(urgent care|hospital|medical|clinic|doctor|physician|dentist|dental|orthodontics|orthodontist|pediatrics|pediatric|dermatology|orthopedics|orthopedic|chiropractic|chiropractor|physical therapy|optometry|optometrist|eye care|pharmacy|veterinary|veterinarian|animal hospital|health|healthcare)\b"#, CategoryMapping(.healthcare)),
        (#"\b(gym|fitness|yoga|pilates|crossfit|martial arts|climbing|boxing|barre)\b"#, CategoryMapping(.fitness)),
        (#"\b(coffee|café|cafe|espresso|tea room|bubble tea|bakery|donut|doughnut|ice cream|gelato|juice)\b"#, CategoryMapping(.cafe)),
        (#"\b(bar|pub|brewery|brewing|taproom|tap room|nightclub|night club|lounge|speakeasy|winery|wine bar|cocktail|beer garden|distillery)\b"#, CategoryMapping(.bar)),
        (#"\b(hotel|hostel|motel|inn|resort|lodge|bed & breakfast|b&b)\b"#, CategoryMapping(.hotel)),
        (#"\b(restaurant|kitchen|grill|pizza|pizzeria|burger|sushi|taco|taqueria|bbq|barbecue|steakhouse|diner|bistro|trattoria|ramen|noodle|deli|sandwich|eatery|cantina)\b"#, CategoryMapping(.restaurant)),
        (#"\b(school|university|college|library|academy)\b"#, CategoryMapping(.education)),
        (#"\b(park|trail|beach|campground|garden|gardens|marina|preserve)\b"#, CategoryMapping(.outdoor)),
        (#"\b(airport|train station|metro|subway|bus station|ferry|gas station|parking)\b"#, CategoryMapping(.transport)),
        (#"\b(bank|credit union|atm)\b"#, CategoryMapping(.finance)),
        (#"\b(museum|gallery|monument|landmark|memorial|cathedral|church|temple|mosque|synagogue)\b"#, CategoryMapping(.attraction)),
        (#"\b(theater|theatre|cinema|movies|arcade|bowling|casino|stadium|arena|zoo|aquarium|amusement)\b"#, CategoryMapping(.entertainment)),
        (#"\b(salon|spa|barber|barbershop|laundry|laundromat|dry clean|dry cleaners|repair|tailor|auto|car wash|vet)\b"#, CategoryMapping(.service)),
        (#"\b(shop|store|market|boutique|mall|bookstore|outlet|supply|hardware)\b"#, CategoryMapping(.retail))
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1) }

    /// nil = nothing in the name gives it away.
    static func mapping(forName name: String?) -> CategoryMapping? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let range = NSRange(name.startIndex..., in: name)
        return nameRules.first { $0.pattern.firstMatch(in: name, options: [], range: range) != nil }?.mapping
    }

    /// "<POI description> in <City>" (or "Located in <City>"), then Phone /
    /// Website lines when Apple supplies them.
    static func description(poiCategory: MKPointOfInterestCategory?, locality: String?, phone: String?, website: URL?) -> String {
        var description = ""
        if let poiCategory = poiCategory {
            description = poiCategory.placeDescription
        }

        // Add location context if available
        if let locality = locality {
            if !description.isEmpty {
                description += " in \(locality)"
            } else {
                description = "Located in \(locality)"
            }
        }

        // Add phone number to description if available
        if let phone = phone {
            description += "\nPhone: \(phone)"
        }

        // Add website to description if available
        if let url = website {
            description += "\nWebsite: \(url.absoluteString)"
        }
        return description
    }
}
