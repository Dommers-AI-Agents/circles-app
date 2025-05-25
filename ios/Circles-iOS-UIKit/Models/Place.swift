import Foundation
import CoreLocation
import MapKit

struct Place: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let address: String
    let location: GeoLocation?
    let website: String?
    let phone: String?
    let googlePlaceId: String?
    let photos: [String]?
    let category: PlaceCategory
    let rating: Double?
    let notes: String?
    let tags: [String]?
    let reviews: [PlaceReview]?
    let openingHours: [OpeningHour]?
    let priceLevel: PriceLevel?
    let circleId: String
    let addedBy: String
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, address, location, website, phone, googlePlaceId
        case photos, category, rating, notes, tags, reviews, openingHours
        case priceLevel, circleId, addedBy, createdAt, updatedAt
    }
}

struct GeoLocation: Codable {
    let type: String
    let coordinates: [Double]
    
    var clLocation: CLLocation? {
        guard coordinates.count == 2 else { return nil }
        // MongoDB stores as [longitude, latitude]
        return CLLocation(latitude: coordinates[1], longitude: coordinates[0])
    }
}

struct PlaceReview: Codable, Identifiable {
    let id: String
    let user: String
    let rating: Double
    let comment: String?
    let date: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case user, rating, comment, date
    }
}

struct OpeningHour: Codable {
    let day: Int // 0 for Sunday, 1 for Monday, etc.
    let open: String // Format: "09:00"
    let close: String // Format: "17:00"
    let isClosed: Bool
}

enum PlaceCategory: String, Codable, CaseIterable {
    case restaurant
    case cafe
    case bar
    case hotel
    case retail
    case service
    case attraction
    case entertainment
    case healthcare
    case fitness
    case education
    case outdoor
    case transport
    case finance
    case other
    
    var displayName: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .bar: return "Bar"
        case .hotel: return "Hotel"
        case .retail: return "Retail"
        case .service: return "Service"
        case .attraction: return "Attraction"
        case .entertainment: return "Entertainment"
        case .healthcare: return "Healthcare"
        case .fitness: return "Fitness"
        case .education: return "Education"
        case .outdoor: return "Outdoor"
        case .transport: return "Transport"
        case .finance: return "Finance"
        case .other: return "Other"
        }
    }
    
    var systemIconName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .hotel: return "bed.double"
        case .retail: return "bag"
        case .service: return "wrench.and.screwdriver"
        case .attraction: return "mappin.and.ellipse"
        case .entertainment: return "ticket"
        case .healthcare: return "heart.text.square"
        case .fitness: return "figure.run"
        case .education: return "book"
        case .outdoor: return "tree"
        case .transport: return "car"
        case .finance: return "dollarsign.circle"
        case .other: return "questionmark.circle"
        }
    }
}

enum PriceLevel: Int, Codable, CaseIterable {
    case free = 0
    case inexpensive = 1
    case moderate = 2
    case expensive = 3
    case veryExpensive = 4
    
    var displaySymbol: String {
        switch self {
        case .free: return "Free"
        case .inexpensive: return "$"
        case .moderate: return "$$"
        case .expensive: return "$$$"
        case .veryExpensive: return "$$$$"
        }
    }
}

// Helper extension to make Place work with MapKit
extension Place {
    func asMapAnnotation() -> PlaceAnnotation {
        return PlaceAnnotation(place: self)
    }
}

// Custom map annotation class for places
class PlaceAnnotation: NSObject, MKAnnotation {
    let place: Place
    
    var coordinate: CLLocationCoordinate2D {
        if let location = place.location?.clLocation {
            return location.coordinate
        }
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    
    var title: String? {
        return place.name
    }
    
    var subtitle: String? {
        return place.category.displayName
    }
    
    init(place: Place) {
        self.place = place
        super.init()
    }
}