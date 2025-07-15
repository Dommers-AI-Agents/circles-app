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
    let customCategoryId: String? // Reference to user's custom category
    let subcategory: String?
    let rating: Double?
    let userRatingsTotal: Int?
    let notes: String? // Legacy field, will be migrated to publicNotes
    let privateNotes: String? // Only visible to the user who added them
    let publicNotes: String? // Visible to all users who can see the place
    let tags: [String]?
    let reviews: [PlaceReview]?
    let openingHours: [OpeningHour]?
    let priceLevel: PriceLevel?
    let likes: [String]?
    let likesCount: Int?
    let commentsCount: Int?
    let circleId: String
    let addedBy: String
    let addedByUser: User? // Populated when fetching places in shared circles
    let privacy: PlacePrivacy
    let createdAt: Date
    let updatedAt: Date
    var isNew: Bool? // Indicates if this is new activity
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, address, location, website, phone, googlePlaceId
        case photos, category, customCategoryId, subcategory, rating, userRatingsTotal, notes, privateNotes, publicNotes, tags, reviews, openingHours
        case priceLevel, likes, likesCount, commentsCount, circleId, addedBy, addedByUser, privacy, createdAt, updatedAt, isNew
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all required fields
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.address = try container.decode(String.self, forKey: .address)
        self.location = try container.decodeIfPresent(GeoLocation.self, forKey: .location)
        self.website = try container.decodeIfPresent(String.self, forKey: .website)
        self.phone = try container.decodeIfPresent(String.self, forKey: .phone)
        self.googlePlaceId = try container.decodeIfPresent(String.self, forKey: .googlePlaceId)
        self.photos = try container.decodeIfPresent([String].self, forKey: .photos)
        self.category = try container.decode(PlaceCategory.self, forKey: .category)
        self.customCategoryId = try container.decodeIfPresent(String.self, forKey: .customCategoryId)
        self.subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        self.rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        self.userRatingsTotal = try container.decodeIfPresent(Int.self, forKey: .userRatingsTotal)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.privateNotes = try container.decodeIfPresent(String.self, forKey: .privateNotes)
        self.publicNotes = try container.decodeIfPresent(String.self, forKey: .publicNotes)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.reviews = try container.decodeIfPresent([PlaceReview].self, forKey: .reviews)
        self.openingHours = try container.decodeIfPresent([OpeningHour].self, forKey: .openingHours)
        
        // Special handling for priceLevel to ignore invalid values like -1
        if let priceLevelInt = try container.decodeIfPresent(Int.self, forKey: .priceLevel),
           let priceLevel = PriceLevel(rawValue: priceLevelInt) {
            self.priceLevel = priceLevel
        } else {
            self.priceLevel = nil
        }
        
        self.likes = try container.decodeIfPresent([String].self, forKey: .likes)
        self.likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
        self.commentsCount = try container.decodeIfPresent(Int.self, forKey: .commentsCount)
        self.circleId = try container.decode(String.self, forKey: .circleId)
        self.addedBy = try container.decode(String.self, forKey: .addedBy)
        self.addedByUser = try container.decodeIfPresent(User.self, forKey: .addedByUser)
        self.privacy = try container.decode(PlacePrivacy.self, forKey: .privacy)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)
    }
    
    // Manual initializer for creating Place instances in code
    init(id: String, name: String, description: String?, address: String,
         location: GeoLocation?, website: String?, phone: String?,
         googlePlaceId: String?, photos: [String]?, category: PlaceCategory,
         customCategoryId: String?, subcategory: String?, rating: Double?, userRatingsTotal: Int?, notes: String?,
         privateNotes: String?, publicNotes: String?, tags: [String]?,
         reviews: [PlaceReview]?, openingHours: [OpeningHour]?,
         priceLevel: PriceLevel?, likes: [String]?, likesCount: Int?, commentsCount: Int?, circleId: String, addedBy: String,
         addedByUser: User?, privacy: PlacePrivacy, createdAt: Date, updatedAt: Date, isNew: Bool? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.address = address
        self.location = location
        self.website = website
        self.phone = phone
        self.googlePlaceId = googlePlaceId
        self.photos = photos
        self.category = category
        self.customCategoryId = customCategoryId
        self.subcategory = subcategory
        self.rating = rating
        self.userRatingsTotal = userRatingsTotal
        self.notes = notes
        self.privateNotes = privateNotes
        self.publicNotes = publicNotes
        self.tags = tags
        self.reviews = reviews
        self.openingHours = openingHours
        self.priceLevel = priceLevel
        self.likes = likes
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.circleId = circleId
        self.addedBy = addedBy
        self.addedByUser = addedByUser
        self.privacy = privacy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isNew = isNew
    }
    
    // Helper computed properties
    var isAddedByCurrentUser: Bool {
        return addedBy == AuthService.shared.getUserId()
    }
    
    var isLikedByCurrentUser: Bool {
        guard let likes = likes, let userId = AuthService.shared.getUserId() else { return false }
        return likes.contains(userId)
    }
    
    var hasPhotos: Bool {
        return photos != nil && !photos!.isEmpty
    }
    
    var displayCategory: String {
        if category == .other, let customCategoryId = customCategoryId, !customCategoryId.isEmpty {
            return customCategoryId
        }
        
        if let subcategory = subcategory, !subcategory.isEmpty {
            return "\(category.displayName) - \(subcategory)"
        }
        
        return category.displayName
    }
    
    var addedByDisplayName: String {
        if isAddedByCurrentUser {
            return "You"
        } else if let user = addedByUser {
            return user.displayName
        }
        return "Unknown"
    }
}

struct GeoLocation: Codable {
    let type: String
    let coordinates: [Double]
    
    var clLocation: CLLocation? {
        guard coordinates.count == 2 else { return nil }
        
        // MongoDB stores as [longitude, latitude]
        let longitude = coordinates[0]
        let latitude = coordinates[1]
        
        // Validate coordinates are within valid ranges
        guard longitude >= -180 && longitude <= 180 &&
              latitude >= -90 && latitude <= 90 else {
            print("❌ Invalid coordinates in GeoLocation: lon=\(longitude), lat=\(latitude)")
            return nil
        }
        
        // Reject coordinates at exactly -180, -180 (invalid/default values)
        if longitude == -180 && latitude == -180 {
            print("❌ Rejecting default invalid coordinates: -180, -180")
            return nil
        }
        
        return CLLocation(latitude: latitude, longitude: longitude)
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
    let open: String? // Format: "09:00"
    let close: String? // Format: "17:00"
    let isClosed: Bool?
    let hours: String? // Legacy field for backward compatibility
    
    enum CodingKeys: String, CodingKey {
        case day, open, close, isClosed, hours
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.day = try container.decode(Int.self, forKey: .day)
        
        // Handle both formats - new format with open/close and old format with hours
        if let hoursString = try container.decodeIfPresent(String.self, forKey: .hours) {
            // Old format - parse hours string
            self.hours = hoursString
            if hoursString.contains("Open 24 hours") {
                self.open = "00:00"
                self.close = "23:59"
            } else if hoursString.contains("Closed") {
                self.open = "00:00"
                self.close = "00:00"
            } else {
                // Try to parse hours from string like "Monday: 9:00 AM – 5:00 PM"
                self.open = "09:00" // Default
                self.close = "17:00" // Default
            }
        } else {
            // New format
            self.hours = nil
            self.open = try container.decodeIfPresent(String.self, forKey: .open) ?? "00:00"
            self.close = try container.decodeIfPresent(String.self, forKey: .close) ?? "00:00"
        }
        
        self.isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed)
    }
    
    // For encoding, always use the new format
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encodeIfPresent(open, forKey: .open)
        try container.encodeIfPresent(close, forKey: .close)
        try container.encodeIfPresent(isClosed, forKey: .isClosed)
        // Don't encode the hours field
    }
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
    case home
    case work
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
        case .home: return "Home"
        case .work: return "Work"
        case .other: return "Other"
        }
    }
    
    var systemIconName: String {
        switch self {
        case .restaurant: return "fork.knife.circle.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .bar: return "wineglass.fill"
        case .hotel: return "bed.double.fill"
        case .retail: return "bag.fill"
        case .service: return "wrench.and.screwdriver.fill"
        case .attraction: return "star.fill"
        case .entertainment: return "music.note.tv.fill"
        case .healthcare: return "heart.text.square.fill"
        case .fitness: return "figure.walk"
        case .education: return "graduationcap.fill"
        case .outdoor: return "tree.fill"
        case .transport: return "car.fill"
        case .finance: return "dollarsign.circle.fill"
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}

// MARK: - Unified Category System
enum UnifiedCategory: Hashable, Equatable {
    case standard(PlaceCategory)
    case custom(String) // Custom category name
    
    var displayName: String {
        switch self {
        case .standard(let category):
            return category.displayName
        case .custom(let name):
            return name
        }
    }
    
    var isCustom: Bool {
        switch self {
        case .standard:
            return false
        case .custom:
            return true
        }
    }
    
    var systemIconName: String {
        switch self {
        case .standard(let category):
            return category.systemIconName
        case .custom:
            return "tag.fill" // Default icon for custom categories
        }
    }
    
    // Helper to match against a Place
    func matches(place: Place) -> Bool {
        switch self {
        case .standard(let category):
            return place.category == category
        case .custom(let name):
            return place.category == .other && place.customCategoryId == name
        }
    }
    
    // Helper to create from a Place
    static func from(place: Place) -> UnifiedCategory {
        if place.category == .other, let customName = place.customCategoryId, !customName.isEmpty {
            return .custom(customName)
        } else {
            return .standard(place.category)
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

enum PlacePrivacy: String, Codable, CaseIterable {
    case followCirclePrivacy = "followCircle"
    case `public` = "public"
    case myNetwork = "myNetwork"
    case `private` = "private"
    
    var displayName: String {
        switch self {
        case .followCirclePrivacy: return "Follow Circle Privacy"
        case .`public`: return "Public"
        case .myNetwork: return "My Network"
        case .`private`: return "Private"
        }
    }
    
    var systemIconName: String {
        switch self {
        case .followCirclePrivacy: return "circle"
        case .`public`: return "globe"
        case .myNetwork: return "person.2"
        case .`private`: return "lock"
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
        // Include owner information when viewing connection places
        let categoryName = place.displayCategory
        let ownerName = place.addedByDisplayName
        
        // Format: "Category • Added by Name"
        return "\(categoryName) • Added by \(ownerName)"
    }
    
    init(place: Place) {
        self.place = place
        super.init()
    }
}