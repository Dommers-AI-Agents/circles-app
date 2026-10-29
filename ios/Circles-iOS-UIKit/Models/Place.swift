import Foundation
import CoreLocation
import MapKit

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
    /// Google service-option flags (venue-owned, overlaid from globalPlaces).
    /// nil = Google hasn't told us; false = definitively not offered. Used to
    /// gate partner action chips (Delivery/Reserve) on the detail screen.
    var delivery: Bool? = nil
    var dineIn: Bool? = nil
    var reservable: Bool? = nil
    var takeout: Bool? = nil
    var curbsidePickup: Bool? = nil
    /// What Google says it serves, whether it's open for business, and its
    /// entrance (free fields of the same Google call); the place page's
    /// "Good to know" line. nil = unknown.
    var serves: PlaceServes? = nil
    var businessStatus: String? = nil
    var wheelchairAccessibleEntrance: Bool? = nil
    /// The saver's own 0–10 score for this place (nil = unrated / "haven't
    /// been yet"). Per-user data on the save record — distinct from `rating`,
    /// which is Google's venue average.
    var userRating: Int? = nil
    /// When `userRating` was last set, and every score the saver ever gave
    /// (oldest first) — "latest wins, history kept".
    var userRatedAt: Date? = nil
    var ratingHistory: [RatingHistoryEntry]? = nil
    let notes: String? // Legacy field, will be migrated to publicNotes
    let privateNotes: String? // Only visible to the user who added them
    /// LEGACY (retired 2026-07-30). Public notes became comments on the venue
    /// — see scripts/migrate-public-notes-to-comments.js. Still decoded because
    /// old/deleted docs carry it; nothing should render or send it.
    let publicNotes: String?
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
    /// The named Inner Circle list this is for, when the tier is that one.
    let audienceListId: String?
    let createdAt: Date
    let updatedAt: Date
    var isNew: Bool? // Indicates if this is new activity
    var circleName: String? // Added by backend for check-in place selection
    var followersCount: Int? = nil // Venue followers (from the canonical global place record)
    var isFollowing: Bool? = nil // Whether the current user follows this venue
    var followAlerts: Bool? = nil // Whether they turned on this venue's alerts (the bell)
    /// The viewer's own check-in history at this venue (place detail only)
    var myCheckInStats: CheckInStats? = nil
    // Derived location lens (cached server-side from the address; see the
    // backend's placeLocationDerivation). Nil on legacy docs the backfill
    // couldn't place — callers fall back to parsing the address.
    var city: String? = nil
    var state: String? = nil          // "North Carolina"
    var stateCode: String? = nil      // "NC"
    var neighborhood: String? = nil   // e.g. Apple subLocality, often nil
    var country: String? = nil        // "Canada" — country-level region chips
    var countryCode: String? = nil    // ISO2, "CA"
    /// Where this save came from: "google_maps" / "mapstr" / "swarm" for
    /// imported rows, nil for places added in the app. Stamped at import time
    /// by the backend; drives the origin flag and the My Places sub-filter.
    var importSource: String? = nil
    /// True on imported rows the background resolver couldn't locate on Apple
    /// Maps (still "Address pending"). Drives the circle-detail review banner;
    /// nil/false for normal places.
    var needsResolution: Bool? = nil
    /// The example place onboarding adds to a new account's first circle;
    /// doesn't count as one of theirs (the "Start your map" card)
    var isSamplePlace: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case globalPlaceId
        case name, description, address, location, website, phone, googlePlaceId
        case photos, videos, category, customCategoryId, subcategory, rating, userRatingsTotal, userRating, notes, privateNotes, publicNotes, tags, reviews, openingHours
        case delivery, dineIn, reservable, takeout, curbsidePickup
        case serves, businessStatus, wheelchairAccessibleEntrance
        case priceLevel, likes, likesCount, commentsCount, circleId, addedBy, addedByUser, privacy, audienceListId, createdAt, updatedAt, isNew, circleName
        case followersCount, isFollowing, followAlerts
        case myCheckInStats
        case userRatedAt, ratingHistory
        case city, state, stateCode, neighborhood, country, countryCode
        case importSource
        case needsResolution
        case isSamplePlace
    }

    /// Human-readable origin for imported saves ("Google import"), nil for
    /// places added in the app.
    var importOriginLabel: String? {
        switch importSource {
        case "google_maps": return "Google import"
        case "mapstr": return "Mapstr import"
        case "swarm": return "Swarm import"
        case "photos": return "From your photos"
        case .some(let other): return "\(other) import"
        case nil: return nil
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all required fields.
        // The id normally arrives as "_id", but embedded places built outside
        // serializeDoc (e.g. a suggestion's placeDetails) can carry only "id" —
        // and one such item must not fail the whole enclosing list's decode.
        if let primaryId = try container.decodeIfPresent(String.self, forKey: .id) {
            self.id = primaryId
        } else {
            struct BareIdKeys: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { return nil }
            }
            let bare = try decoder.container(keyedBy: BareIdKeys.self)
            self.id = try bare.decode(String.self, forKey: BareIdKeys(stringValue: "id")!)
        }
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
            Logger.debug("🔴 ALERT: Place decoded with suspicious customCategoryId!")
            Logger.debug("🔴 Place ID: \(self.id)")
            Logger.debug("🔴 Name: \(self.name)")
            Logger.debug("🔴 Category: \(category.rawValue)")
            Logger.debug("🔴 CustomCategoryId: '\(customCategoryId)'")
            Logger.debug("🔴 This appears to be user data, not a category name!")
        }
        self.subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        self.rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        self.userRatingsTotal = try container.decodeIfPresent(Int.self, forKey: .userRatingsTotal)
        self.userRating = try container.decodeIfPresent(Int.self, forKey: .userRating)
        self.userRatedAt = try? container.decodeIfPresent(Date.self, forKey: .userRatedAt)
        self.ratingHistory = try? container.decodeIfPresent([RatingHistoryEntry].self, forKey: .ratingHistory)
        self.delivery = try? container.decodeIfPresent(Bool.self, forKey: .delivery)
        self.dineIn = try? container.decodeIfPresent(Bool.self, forKey: .dineIn)
        self.reservable = try? container.decodeIfPresent(Bool.self, forKey: .reservable)
        self.takeout = try? container.decodeIfPresent(Bool.self, forKey: .takeout)
        self.curbsidePickup = try? container.decodeIfPresent(Bool.self, forKey: .curbsidePickup)
        self.serves = try? container.decodeIfPresent(PlaceServes.self, forKey: .serves)
        self.businessStatus = try? container.decodeIfPresent(String.self, forKey: .businessStatus)
        self.wheelchairAccessibleEntrance = try? container.decodeIfPresent(Bool.self, forKey: .wheelchairAccessibleEntrance)
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
        self.audienceListId = try container.decodeIfPresent(String.self, forKey: .audienceListId)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)
        self.followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount)
        self.isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing)
        self.followAlerts = try container.decodeIfPresent(Bool.self, forKey: .followAlerts)
        self.myCheckInStats = try container.decodeIfPresent(CheckInStats.self, forKey: .myCheckInStats)
        self.city = try container.decodeIfPresent(String.self, forKey: .city)
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
        self.stateCode = try container.decodeIfPresent(String.self, forKey: .stateCode)
        self.neighborhood = try container.decodeIfPresent(String.self, forKey: .neighborhood)
        self.country = try container.decodeIfPresent(String.self, forKey: .country)
        self.countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        self.importSource = try container.decodeIfPresent(String.self, forKey: .importSource)
        self.needsResolution = try container.decodeIfPresent(Bool.self, forKey: .needsResolution)
        self.isSamplePlace = try container.decodeIfPresent(Bool.self, forKey: .isSamplePlace)
    }
    
    // Manual initializer for creating Place instances in code
    init(id: String, globalPlaceId: String? = nil, name: String, description: String?, address: String,
         location: GeoLocation?, website: String?, phone: String?,
         googlePlaceId: String?, photos: [String]?, videos: [String]?, category: PlaceCategory,
         customCategoryId: String?, subcategory: String?, rating: Double?, userRatingsTotal: Int?, notes: String?,
         privateNotes: String?, publicNotes: String?, tags: [String]?,
         reviews: [PlaceReview]?, openingHours: [OpeningHour]?,
         priceLevel: PriceLevel?, likes: [String]?, likesCount: Int?, commentsCount: Int?, circleId: String?, addedBy: String,
         addedByUser: User?, privacy: PlacePrivacy, audienceListId: String? = nil, createdAt: Date, updatedAt: Date, isNew: Bool? = nil,
         userRating: Int? = nil) {
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
        self.audienceListId = audienceListId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isNew = isNew
        self.userRating = userRating
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
            Logger.debug("❌ Invalid coordinates in GeoLocation: lon=\(longitude), lat=\(latitude)")
            return nil
        }
        
        // Reject coordinates at exactly -180, -180 (invalid/default values)
        if longitude == -180 && latitude == -180 {
            Logger.debug("❌ Rejecting default invalid coordinates: -180, -180")
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
    
    /// The SF Symbol for this category in a list row. Lived as a copy-pasted
    /// switch in two search cells before this; one table, one answer.
    var symbolName: String {
        switch self {
        case .restaurant, .cafe, .bar: return "fork.knife"
        case .hotel: return "bed.double"
        case .retail: return "bag"
        case .service: return "wrench.and.screwdriver"
        case .attraction: return "star"
        case .entertainment: return "tv"
        case .healthcare: return "heart"
        case .fitness: return "figure.walk"
        case .education: return "graduationcap"
        case .outdoor: return "tree"
        case .transport: return "car"
        case .finance: return "dollarsign.circle"
        case .home: return "house"
        case .work: return "building.2"
        case .other: return "circle.grid.3x3"
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

/// A place's own privacy. It can only NARROW what its circle already allows —
/// `followCircle` (the default, and all the Add Place screen can produce) adds
/// nothing. Display strings live on `PrivacyOption`; see Logic/PrivacyTier.swift.
enum PlacePrivacy: String, Codable {
    case followCirclePrivacy = "followCircle"
    case `public` = "public"
    case myNetwork = "myNetwork"
    case innerCircle = "innerCircle"
    case `private` = "private"
    /// A value a newer build understands and this one does not. Decoded rather
    /// than thrown so the place still appears, shown as Private, never saved.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlacePrivacy(rawValue: raw) ?? .unknown
    }

    /// The picker option this corresponds to, or nil if we don't recognise it.
    var option: PrivacyOption? {
        if self == .followCirclePrivacy { return .inheritCircle }
        guard let tier = PrivacyTier(rawValue: rawValue) else { return nil }
        return .tier(tier)
    }

    var displayName: String { option?.title ?? PrivacyTier.private.title }

    var systemIconName: String { option?.systemIconName ?? PrivacyTier.private.systemIconName }
}

extension PrivacyOption {
    /// The stored place value for this option, or nil if it isn't one a place
    /// can hold (moments' followers audience).
    var placePrivacy: PlacePrivacy? {
        switch self {
        case .inheritCircle: return .followCirclePrivacy
        case .followers: return nil
        case .tier(let tier): return PlacePrivacy(rawValue: tier.rawValue)
        }
    }
}

// Helper extension to make Place work with MapKit
extension Place {
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
