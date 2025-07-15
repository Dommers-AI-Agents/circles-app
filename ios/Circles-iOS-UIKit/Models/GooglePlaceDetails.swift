import Foundation
import GooglePlaces
import CoreLocation

struct GooglePlaceDetails {
    let placeID: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let phoneNumber: String?
    let website: URL?
    let rating: Double?
    let userRatingsTotal: Int
    let priceLevel: PriceLevel?
    let types: [String]
    let photos: [GMSPlacePhotoMetadata]
    let openingHours: GMSOpeningHours?
    let isOpen: Bool?
    
    init(from gmsPlace: GMSPlace) {
        self.placeID = gmsPlace.placeID ?? ""
        self.name = gmsPlace.name ?? "Unknown Place"
        self.address = gmsPlace.formattedAddress
        self.coordinate = gmsPlace.coordinate
        self.phoneNumber = gmsPlace.phoneNumber
        self.website = gmsPlace.website
        // rating is Float, not optional
        self.rating = gmsPlace.rating > 0 ? Double(gmsPlace.rating) : nil
        // userRatingsTotal is UInt, not optional
        self.userRatingsTotal = Int(gmsPlace.userRatingsTotal)
        // priceLevel is GMSPlacesPriceLevel enum
        if gmsPlace.priceLevel != .unknown {
            self.priceLevel = Self.mapPriceLevel(gmsPlace.priceLevel)
        } else {
            self.priceLevel = nil
        }
        self.types = gmsPlace.types ?? []
        self.photos = gmsPlace.photos ?? []
        self.openingHours = gmsPlace.openingHours
        // isOpen returns GMSPlaceOpenStatus enum
        let openStatus = gmsPlace.isOpen()
        self.isOpen = openStatus == .open ? true : (openStatus == .closed ? false : nil)
    }
    
    // Custom initializer for manually created places (e.g., from address geocoding)
    init(placeID: String,
         name: String,
         address: String?,
         coordinate: CLLocationCoordinate2D,
         phoneNumber: String? = nil,
         website: URL? = nil,
         rating: Double? = nil,
         userRatingsTotal: Int = 0,
         priceLevel: PriceLevel? = nil,
         types: [String] = [],
         photos: [GMSPlacePhotoMetadata] = [],
         openingHours: GMSOpeningHours? = nil,
         isOpen: Bool? = nil) {
        self.placeID = placeID
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.phoneNumber = phoneNumber
        self.website = website
        self.rating = rating
        self.userRatingsTotal = userRatingsTotal
        self.priceLevel = priceLevel
        self.types = types
        self.photos = photos
        self.openingHours = openingHours
        self.isOpen = isOpen
    }
    
    // Convert to our Place model format
    func toPlaceData(circleId: String, notes: String? = nil, customCategory: PlaceCategory? = nil) -> [String: Any] {
        let category = customCategory ?? Self.mapGooglePlaceTypeToCategory(types)
        
        var data: [String: Any] = [
            "name": name,
            "address": address ?? "",
            "googlePlaceId": placeID,
            "category": category.rawValue,
            "circleId": circleId,
            "location": [
                "type": "Point",
                "coordinates": [coordinate.longitude, coordinate.latitude]
            ]
        ]
        
        // Add optional fields
        if let phoneNumber = phoneNumber {
            data["phone"] = phoneNumber
        }
        
        if let website = website {
            data["website"] = website.absoluteString
        }
        
        if let rating = rating {
            data["rating"] = rating
            data["userRatingsTotal"] = userRatingsTotal
        }
        
        if let priceLevel = priceLevel {
            data["priceLevel"] = priceLevel.rawValue
        }
        
        if let notes = notes, !notes.isEmpty {
            data["notes"] = notes
        }
        
        // Add opening hours if available
        if let openingHours = openingHours {
            data["openingHours"] = formatOpeningHours(openingHours)
        }
        
        // Add current open status
        if let isOpen = isOpen {
            data["isOpenNow"] = isOpen
        }
        
        return data
    }
    
    private func formatOpeningHours(_ hours: GMSOpeningHours) -> [[String: Any]] {
        var formattedHours: [[String: Any]] = []
        
        guard let periods = hours.periods else { return formattedHours }
        
        for period in periods {
            var hourData: [String: Any] = [
                "day": period.openEvent.day.rawValue,
                "open": formatTime(period.openEvent.time)
            ]
            
            if let closeEvent = period.closeEvent {
                hourData["close"] = formatTime(closeEvent.time)
            } else {
                // 24 hour place or no close time
                hourData["close"] = "23:59"
            }
            
            formattedHours.append(hourData)
        }
        
        return formattedHours
    }
    
    private func formatTime(_ time: GMSTime) -> String {
        return String(format: "%02d:%02d", time.hour, time.minute)
    }
    
    // MARK: - Helper Methods (moved from GooglePlacesService)
    
    static func mapPriceLevel(_ priceLevel: GMSPlacesPriceLevel) -> PriceLevel {
        switch priceLevel {
        case .free: return .free
        case .cheap: return .inexpensive
        case .medium: return .moderate
        case .high: return .expensive
        case .expensive: return .veryExpensive
        @unknown default: return .moderate
        }
    }
    
    static func mapGooglePlaceTypeToCategory(_ types: [String]?) -> PlaceCategory {
        guard let types = types else { return .other }
        
        // Map Google place types to our categories
        if types.contains("restaurant") { return .restaurant }
        if types.contains("cafe") { return .cafe }
        if types.contains("bar") || types.contains("night_club") { return .bar }
        if types.contains("lodging") || types.contains("hotel") { return .hotel }
        if types.contains("store") || types.contains("shopping_mall") { return .retail }
        if types.contains("health") || types.contains("hospital") || types.contains("doctor") { return .healthcare }
        if types.contains("gym") || types.contains("spa") { return .fitness }
        if types.contains("school") || types.contains("university") { return .education }
        if types.contains("park") || types.contains("campground") { return .outdoor }
        if types.contains("transit_station") || types.contains("gas_station") { return .transport }
        if types.contains("bank") || types.contains("atm") { return .finance }
        if types.contains("movie_theater") || types.contains("museum") || types.contains("stadium") { return .entertainment }
        if types.contains("tourist_attraction") || types.contains("point_of_interest") { return .attraction }
        
        return .other
    }
}

// Extension to help with autocomplete predictions
struct GooglePlacePrediction {
    let placeID: String
    let primaryText: String
    let secondaryText: String
    let fullText: String
    let types: [String]
    
    init(from prediction: GMSAutocompletePrediction) {
        self.placeID = prediction.placeID
        self.primaryText = prediction.attributedPrimaryText.string
        self.secondaryText = prediction.attributedSecondaryText?.string ?? ""
        self.fullText = prediction.attributedFullText.string
        self.types = prediction.types
    }
}