import MapKit

extension MKPointOfInterestCategory {
    /// A one-line description of an Apple Maps point-of-interest category,
    /// used as the default description when a place is added from a map
    /// result. Shared by the add-place form and place search.
    var placeDescription: String {
        switch self {
        case .restaurant: return "A dining establishment"
        case .cafe: return "A coffee shop or casual dining spot"
        case .nightlife, .brewery, .winery: return "A bar or nightlife venue"
        case .hotel, .campground: return "Accommodation services"
        case .store, .foodMarket: return "Retail shopping location"
        case .gasStation, .evCharger: return "Vehicle fueling or charging station"
        case .parking: return "Parking facility"
        case .carRental: return "Car rental services"
        case .laundry: return "Laundry services"
        case .postOffice: return "Postal services"
        case .bank, .atm: return "Banking and financial services"
        case .pharmacy: return "Pharmacy and medication services"
        case .hospital: return "Healthcare services"
        case .fireStation, .police: return "Emergency services"
        case .publicTransport: return "Public transportation"
        case .school, .university: return "Educational institution"
        case .library: return "Library and information services"
        case .movieTheater: return "Movie theater entertainment"
        case .museum: return "Museum and cultural exhibits"
        case .park, .beach, .nationalPark: return "Outdoor recreation area"
        case .theater: return "Theater and performing arts venue"
        case .zoo, .aquarium: return "Animal exhibits and attractions"
        case .amusementPark: return "Amusement park and rides"
        case .stadium: return "Sports and event venue"
        case .marina: return "Marina and boating services"
        default:
            if #available(iOS 18.0, *) {
                switch self {
                case .miniGolf: return "Mini golf recreation"
                case .castle, .landmark: return "Historical landmark or attraction"
                default: return "Local business or point of interest"
                }
            } else {
                return "Local business or point of interest"
            }
        }
    }
}
