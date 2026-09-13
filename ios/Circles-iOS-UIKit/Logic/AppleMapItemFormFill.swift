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

    static func categoryMapping(poiCategory: MKPointOfInterestCategory?, name: String?) -> CategoryMapping {
        if let poiCategory = poiCategory {
            switch poiCategory {
            case .restaurant: return CategoryMapping(.restaurant)
            case .cafe: return CategoryMapping(.cafe, "Coffee Shop")
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
            case .parking: return CategoryMapping(.transport, "Parking")
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
                    case .miniGolf: return CategoryMapping(.entertainment)
                    case .castle, .landmark: return CategoryMapping(.attraction, "Landmark")
                    default: return CategoryMapping(.other)
                    }
                } else {
                    return CategoryMapping(.other)
                }
            }
        }

        // Try to infer category from name
        let lowered = (name ?? "").lowercased()
        if lowered.contains("restaurant") || lowered.contains("kitchen") || lowered.contains("grill") {
            return CategoryMapping(.restaurant)
        } else if lowered.contains("cafe") || lowered.contains("coffee") {
            return CategoryMapping(.cafe)
        } else if lowered.contains("bar") || lowered.contains("pub") || lowered.contains("brewery") {
            return CategoryMapping(.bar)
        } else if lowered.contains("hotel") || lowered.contains("inn") || lowered.contains("motel") {
            return CategoryMapping(.hotel)
        } else if lowered.contains("store") || lowered.contains("shop") || lowered.contains("market") {
            return CategoryMapping(.retail)
        }
        return CategoryMapping(.other)
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
