import Foundation
import CoreLocation
import MapKit

// Helper for flexible JSON decoding
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

/// Decodes array elements individually, dropping any that fail instead of
/// failing the entire array. One malformed record in a list response must not
/// blank a whole screen - this has bitten twice (a place with a location
/// missing its GeoJSON type broke profiles; string-format openingHours broke
/// check-in).
struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct AnyDecodableValue: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else {
                // Skip the malformed element and keep going
                _ = try? container.decode(AnyDecodableValue.self)
                print("⚠️ LossyDecodableArray: dropped malformed \(Element.self) element")
            }
        }
        self.elements = decoded
    }
}

struct Place: Codable, Identifiable {
    let id: String
    let globalPlaceId: String? // Reference to Global Place system
    let name: String
    let description: String?
    let address: String
    let location: GeoLocation?
    let website: String?
    let phone: String?
    let googlePlaceId: String?
    let photos: [String]?
    let videos: [String]?
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
    let circleId: String?
    let addedBy: String
    let addedByUser: User? // Populated when fetching places in shared circles
    let privacy: PlacePrivacy
    let createdAt: Date
    let updatedAt: Date
    var isNew: Bool? // Indicates if this is new activity
    var circleName: String? // Added by backend for check-in place selection
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case globalPlaceId
        case name, description, address, location, website, phone, googlePlaceId
        case photos, videos, category, customCategoryId, subcategory, rating, userRatingsTotal, notes, privateNotes, publicNotes, tags, reviews, openingHours
        case priceLevel, likes, likesCount, commentsCount, circleId, addedBy, addedByUser, privacy, createdAt, updatedAt, isNew, circleName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all required fields
        self.id = try container.decode(String.self, forKey: .id)
        self.globalPlaceId = try container.decodeIfPresent(String.self, forKey: .globalPlaceId)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.address = try container.decode(String.self, forKey: .address)
        self.location = try container.decodeIfPresent(GeoLocation.self, forKey: .location)
        self.website = try container.decodeIfPresent(String.self, forKey: .website)
        self.phone = try container.decodeIfPresent(String.self, forKey: .phone)
        self.googlePlaceId = try container.decodeIfPresent(String.self, forKey: .googlePlaceId)
        // Handle mixed photo data types (strings and objects with metadata)
        if let photosContainer = try? container.nestedUnkeyedContainer(forKey: .photos) {
            var photos: [String] = []
            var photosContainerCopy = photosContainer
            
            while !photosContainerCopy.isAtEnd {
                if let photoString = try? photosContainerCopy.decode(String.self) {
                    // Handle simple string URLs
                    photos.append(photoString)
                } else if let photoDict = try? photosContainerCopy.decode([String: AnyCodable].self),
                          let url = photoDict["url"]?.value as? String {
                    // Handle photo objects with metadata - extract URL
                    photos.append(url)
                } else {
                    // Skip unknown format
                    _ = try? photosContainerCopy.decode(AnyCodable.self)
                }
            }
            self.photos = photos.isEmpty ? nil : photos
        } else {
            self.photos = try container.decodeIfPresent([String].self, forKey: .photos)
        }
        self.videos = try container.decodeIfPresent([String].self, forKey: .videos)
        self.category = try container.decode(PlaceCategory.self, forKey: .category)
        self.customCategoryId = try container.decodeIfPresent(String.self, forKey: .customCategoryId)
        
        // Debug: Check for suspicious customCategoryId values during decoding
        if let customCategoryId = self.customCategoryId, 
           category == .other,
           (customCategoryId.contains("@") || 
            (customCategoryId.components(separatedBy: " ").count == 2 && 
             customCategoryId != "Other" && 
             !customCategoryId.isEmpty)) {
            print("🔴 ALERT: Place decoded with suspicious customCategoryId!")
            print("🔴 Place ID: \(self.id)")
            print("🔴 Name: \(self.name)")
            print("🔴 Category: \(category.rawValue)")
            print("🔴 CustomCategoryId: '\(customCategoryId)'")
            print("🔴 This appears to be user data, not a category name!")
        }
        self.subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        self.rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        self.userRatingsTotal = try container.decodeIfPresent(Int.self, forKey: .userRatingsTotal)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.privateNotes = try container.decodeIfPresent(String.self, forKey: .privateNotes)
        self.publicNotes = try container.decodeIfPresent(String.self, forKey: .publicNotes)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.reviews = try container.decodeIfPresent([PlaceReview].self, forKey: .reviews)
        // Lenient: legacy places stored openingHours as plain strings; a malformed
        // entry should drop the field, not fail the entire response decode
        self.openingHours = (try? container.decodeIfPresent([OpeningHour].self, forKey: .openingHours)) ?? nil
        
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
        self.circleId = try container.decodeIfPresent(String.self, forKey: .circleId)
        self.addedBy = try container.decode(String.self, forKey: .addedBy)
        self.addedByUser = try container.decodeIfPresent(User.self, forKey: .addedByUser)
        self.privacy = try container.decode(PlacePrivacy.self, forKey: .privacy)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)
    }
    
    // Manual initializer for creating Place instances in code
    init(id: String, globalPlaceId: String? = nil, name: String, description: String?, address: String,
         location: GeoLocation?, website: String?, phone: String?,
         googlePlaceId: String?, photos: [String]?, videos: [String]?, category: PlaceCategory,
         customCategoryId: String?, subcategory: String?, rating: Double?, userRatingsTotal: Int?, notes: String?,
         privateNotes: String?, publicNotes: String?, tags: [String]?,
         reviews: [PlaceReview]?, openingHours: [OpeningHour]?,
         priceLevel: PriceLevel?, likes: [String]?, likesCount: Int?, commentsCount: Int?, circleId: String?, addedBy: String,
         addedByUser: User?, privacy: PlacePrivacy, createdAt: Date, updatedAt: Date, isNew: Bool? = nil) {
        self.id = id
        self.globalPlaceId = globalPlaceId
        self.name = name
        self.description = description
        self.address = address
        self.location = location
        self.website = website
        self.phone = phone
        self.googlePlaceId = googlePlaceId
        self.photos = photos
        self.videos = videos
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
    
    // Manual initializer for creating PlaceReview instances in code
    init(id: String, user: String, rating: Double, comment: String?, date: Date) {
        self.id = id
        self.user = user
        self.rating = rating
        self.comment = comment
        self.date = date
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
    
    var color: UIColor {
        switch self {
        case .restaurant:
            return UIColor(hex: "#E53E3E") // Red
        case .cafe:
            return UIColor(hex: "#DD6B20") // Orange
        case .bar:
            return UIColor(hex: "#DD6B20") // Orange
        case .hotel:
            return UIColor(hex: "#3182CE") // Blue
        case .retail:
            return UIColor(hex: "#805AD5") // Purple
        case .service:
            return UIColor(hex: "#38A169") // Green
        case .attraction:
            return UIColor(hex: "#D69E2E") // Yellow
        case .entertainment:
            return UIColor(hex: "#D69E2E") // Yellow
        case .healthcare:
            return UIColor(hex: "#319795") // Teal
        case .fitness:
            return UIColor(hex: "#E53E3E") // Red
        case .education:
            return UIColor(hex: "#3182CE") // Blue
        case .outdoor:
            return UIColor(hex: "#22C55E") // Green
        case .transport:
            return UIColor(hex: "#718096") // Gray
        case .finance:
            return UIColor(hex: "#10B981") // Emerald
        case .home:
            return UIColor(hex: "#8B5CF6") // Violet
        case .work:
            return UIColor(hex: "#6366F1") // Indigo
        case .other:
            return UIColor(hex: "#38A169") // Green
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
    
    var color: UIColor {
        switch self {
        case .standard(let category):
            return category.color
        case .custom:
            return UIColor(hex: "#718096") // Gray for custom categories
        }
    }
    
    // Helper to match against a Place
    func matches(place: Place) -> Bool {
        switch self {
        case .standard(let category):
            return place.category == category
        case .custom(let name):
            // Custom categories are stored as: category: .other, customCategoryId: "Category Name"
            let matches = place.category == .other && place.customCategoryId == name
            
            // Debug logging for custom category matching
            if !matches {
                print("🚫 Custom category '\(name)' does not match place '\(place.name)' - place category: \(place.category.rawValue), customCategoryId: '\(place.customCategoryId ?? "none")'")
            } else {
                print("✅ Custom category '\(name)' matches place '\(place.name)'")
            }
            
            return matches
        }
    }
    
    // Helper to create from a Place
    static func from(place: Place) -> UnifiedCategory {
        if place.category == .other, let customName = place.customCategoryId, !customName.isEmpty {
            // Validate that this is actually a category name and not user data
            if isValidCategoryName(customName) {
                // Check for custom categories that should map to standard categories
                if let standardCategory = mapCustomToStandardCategory(customName) {
                    return .standard(standardCategory)
                }
                return .custom(customName)
            } else {
                // Fall back to "Other" category if invalid
                print("⚠️ Invalid custom category detected: '\(customName)' - falling back to Other")
                return .standard(.other)
            }
        } else {
            return .standard(place.category)
        }
    }
    
    // Map custom category names to standard categories to prevent duplicates
    private static func mapCustomToStandardCategory(_ customName: String) -> PlaceCategory? {
        let normalizedName = customName.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Healthcare variations
        if normalizedName == "healthcare" || normalizedName == "health care" || normalizedName == "medical" {
            return .healthcare
        }
        
        // Restaurant variations  
        if normalizedName == "restaurant" || normalizedName == "restaurants" {
            return .restaurant
        }
        
        // Cafe variations
        if normalizedName == "cafe" || normalizedName == "café" || normalizedName == "coffee" {
            return .cafe
        }
        
        // Bar variations
        if normalizedName == "bar" || normalizedName == "bars" || normalizedName == "pub" {
            return .bar
        }
        
        // Retail variations
        if normalizedName == "retail" || normalizedName == "shopping" || normalizedName == "store" {
            return .retail
        }
        
        // Hotel variations
        if normalizedName == "hotel" || normalizedName == "accommodation" || normalizedName == "lodging" {
            return .hotel
        }
        
        // Service variations
        if normalizedName == "service" || normalizedName == "services" {
            return .service
        }
        
        // Entertainment variations
        if normalizedName == "entertainment" || normalizedName == "nightclub" {
            return .entertainment
        }
        
        // Fitness variations
        if normalizedName == "fitness" || normalizedName == "gym" || normalizedName == "health club" {
            return .fitness
        }
        
        // Attraction variations
        if normalizedName == "attraction" || normalizedName == "tourist" || normalizedName == "sightseeing" {
            return .attraction
        }
        
        // Home variations
        if normalizedName == "home" || normalizedName == "house" || normalizedName == "residence" {
            return .home
        }
        
        // Work variations
        if normalizedName == "work" || normalizedName == "office" || normalizedName == "workplace" {
            return .work
        }
        
        return nil // No mapping found, keep as custom category
    }
    
    // Validate that a string is a valid category name (not an email or user ID)
    private static func isValidCategoryName(_ name: String) -> Bool {
        // Check if it looks like an email
        if name.contains("@") && name.contains(".") {
            return false
        }
        
        // Check if it's a numeric ID
        if name.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil && name.count > 10 {
            return false
        }
        
        // Check if it contains typical user name patterns (firstname lastname)
        let components = name.components(separatedBy: " ")
        if components.count == 2 {
            // Check if both components start with capital letters (typical for names)
            let firstComponent = components[0]
            let secondComponent = components[1]
            if !firstComponent.isEmpty && !secondComponent.isEmpty {
                let firstChar = String(firstComponent.prefix(1))
                let secondChar = String(secondComponent.prefix(1))
                if firstChar == firstChar.uppercased() && secondChar == secondChar.uppercased() {
                    // Likely a person's name, not a category
                    return false
                }
            }
        }
        
        // Additional checks for known invalid patterns
        let invalidPatterns = ["admin", "user", "test"]
        let lowercaseName = name.lowercased()
        for pattern in invalidPatterns {
            if lowercaseName == pattern {
                return false
            }
        }
        
        return true
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

// MARK: - Place Array Filtering Extensions
extension Array where Element == Place {
    // Filter by category
    func filtered(by category: UnifiedCategory?) -> [Place] {
        guard let category = category else { return self }
        return self.filter { category.matches(place: $0) }
    }
    
    // Filter by connection (for "My Places Only" etc)
    func filtered(by connectionId: String?, currentUserId: String) -> [Place] {
        guard let connectionId = connectionId else { return self }
        
        if connectionId == "my_places_only" {
            // Show only user's own places
            return self.filter { $0.addedBy == currentUserId }
        } else {
            // Show only places from the selected connection
            return self.filter { $0.addedBy == connectionId }
        }
    }
    
    // Filter by city
    func filtered(by city: String?) -> [Place] {
        guard let city = city else { return self }
        return self.filter { place in
            // Extract city from address (assumes format: "..., City, State/Country")
            let components = place.address.components(separatedBy: ", ")
            if components.count >= 2 {
                let cityComponent = components[components.count - 2]
                return cityComponent.localizedCaseInsensitiveContains(city)
            }
            return false
        }
    }
    
    // Combined filter method
    func filtered(category: UnifiedCategory? = nil,
                 connectionId: String? = nil,
                 city: String? = nil,
                 currentUserId: String) -> [Place] {
        var result = self
        
        // Apply filters in sequence
        result = result.filtered(by: category)
        result = result.filtered(by: connectionId, currentUserId: currentUserId)
        result = result.filtered(by: city)
        
        return result
    }
}

// MARK: - Category Utilities
extension PlaceCategory {
    // Get all unique categories from a list of places
    static func uniqueCategories(from places: [Place]) -> [UnifiedCategory] {
        var categoriesSet = Set<UnifiedCategory>()
        
        for place in places {
            categoriesSet.insert(UnifiedCategory.from(place: place))
        }
        
        return categoriesSet.sorted(by: { $0.displayName < $1.displayName })
    }
}

// MARK: - Place Utilities
extension Array where Element == Place {
    // Get available cities from places
    func uniqueCities() -> [String] {
        var citiesSet = Set<String>()
        
        for place in self {
            // Extract city from address (assumes format: "..., City, State/Country")
            let components = place.address.components(separatedBy: ", ")
            if components.count >= 2 {
                let city = components[components.count - 2].trimmingCharacters(in: .whitespaces)
                if !city.isEmpty {
                    citiesSet.insert(city)
                }
            }
        }
        
        return citiesSet.sorted()
    }
}

// Helper extension to make Place work with MapKit
extension Place {
    func asMapAnnotation() -> PlaceAnnotation {
        return PlaceAnnotation(place: self)
    }
    
    // Convenience properties for accessing coordinates
    var latitude: Double? {
        guard let location = location,
              location.coordinates.count == 2 else { return nil }
        // MongoDB stores as [longitude, latitude]
        return location.coordinates[1]
    }
    
    var longitude: Double? {
        guard let location = location,
              location.coordinates.count == 2 else { return nil }
        // MongoDB stores as [longitude, latitude]
        return location.coordinates[0]
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
        // Add "NEW" prefix if this is a new place
        return (place.isNew == true ? "🆕 " : "") + place.name
    }
    
    var subtitle: String? {
        // Always show who added the place
        return "Added by \(place.addedByDisplayName)"
    }
    
    init(place: Place) {
        self.place = place
        super.init()
    }
}