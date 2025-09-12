import Foundation
import CoreLocation
import MapKit

// MARK: - Global Place Model
struct GlobalPlace: Codable, Identifiable {
    let id: String
    let googlePlaceId: String?
    let name: String
    let address: String
    let location: GeoLocation?
    let category: PlaceCategory
    let subcategory: String?
    
    // Unified media with attribution
    let photos: [AttributedPhoto]?
    let videos: [AttributedVideo]?
    
    // Public content shared across platform
    let publicReviews: [PublicReview]?
    
    // Aggregated statistics
    let userContributions: UserContributions
    
    // Google Places API data (cached)
    let googleData: GooglePlaceData?
    
    // Platform statistics
    let totalCircleReferences: Int
    let totalUserReferences: Int
    let lastActivityAt: Date
    
    let dataCompleteness: Double
    let qualityScore: Double
    
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case googlePlaceId, name, address, location, category, subcategory
        case photos, videos, publicReviews, userContributions, googleData
        case totalCircleReferences, totalUserReferences, lastActivityAt
        case dataCompleteness, qualityScore
        case createdAt, updatedAt, deletedAt
    }
}

// MARK: - Attributed Media
struct AttributedPhoto: Codable, Identifiable {
    let id = UUID()
    let url: String
    let uploadedBy: String
    let uploadedByName: String?
    let uploadedAt: Date
    let source: MediaSource
    let width: Int?
    let height: Int?
    let fileSize: Int64?
    
    enum CodingKeys: String, CodingKey {
        case url, uploadedBy, uploadedByName, uploadedAt, source
        case width, height, fileSize
    }
}

struct AttributedVideo: Codable, Identifiable {
    let id = UUID()
    let videoUrl: String
    let thumbnailUrl: String?
    let previewUrl: String?
    let uploadedBy: String
    let uploadedByName: String?
    let uploadedAt: Date
    let title: String
    let description: String
    let duration: TimeInterval
    let fileSize: Int64
    let source: MediaSource
    
    enum CodingKeys: String, CodingKey {
        case videoUrl, thumbnailUrl, previewUrl, uploadedBy, uploadedByName
        case uploadedAt, title, description, duration, fileSize, source
    }
}

enum MediaSource: String, Codable {
    case userUpload = "user_upload"
    case googlePlaces = "google_places"
    
    var displayName: String {
        switch self {
        case .userUpload:
            return "User Upload"
        case .googlePlaces:
            return "Google Places"
        }
    }
}

// MARK: - Public Review
struct PublicReview: Codable, Identifiable {
    let id = UUID()
    let userId: String
    let userName: String
    let userPhoto: String?
    let text: String
    let rating: Double?
    let photos: [String]?
    let createdAt: Date
    let updatedAt: Date
    let likes: [String]
    let likesCount: Int
    let isVerified: Bool
    let helpfulCount: Int
    let reportCount: Int
    
    enum CodingKeys: String, CodingKey {
        case userId, userName, userPhoto, text, rating, photos
        case createdAt, updatedAt, likes, likesCount, isVerified
        case helpfulCount, reportCount
    }
    
    // Helper computed properties
    var isLikedByCurrentUser: Bool {
        guard let currentUserId = AuthService.shared.getUserId() else { return false }
        return likes.contains(currentUserId)
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var formattedRating: String? {
        guard let rating = rating else { return nil }
        return String(format: "%.1f", rating)
    }
}

// MARK: - User Contributions
struct UserContributions: Codable {
    let totalPhotos: Int
    let totalVideos: Int
    let totalReviews: Int
    let contributors: [String]
    
    var totalContributions: Int {
        return totalPhotos + totalVideos + totalReviews
    }
    
    var contributorCount: Int {
        return contributors.count
    }
}

// MARK: - Google Place Data
struct GooglePlaceData: Codable {
    let rating: Double?
    let userRatingsTotal: Int?
    let priceLevel: PriceLevel?
    let openingHours: [OpeningHour]?
    let website: String?
    let phone: String?
    let lastRefreshedAt: Date?
}

// MARK: - User Place Relation
struct UserPlaceRelation: Codable, Identifiable {
    let id: String
    let userId: String
    let placeId: String
    let circleId: String
    
    // User-specific data
    let privateNotes: String?
    let personalRating: Double?
    let visitDates: [Date]?
    let tags: [String]?
    
    // Relationship metadata
    let addedAt: Date
    let lastVisited: Date?
    let privacy: PlacePrivacy
    
    // Activity tracking
    let lastAccessedAt: Date
    let viewCount: Int
    let shareCount: Int
    
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, placeId, circleId
        case privateNotes, personalRating, visitDates, tags
        case addedAt, lastVisited, privacy
        case lastAccessedAt, viewCount, shareCount
        case createdAt, updatedAt
    }
}

// MARK: - Combined Place Response
struct GlobalPlaceResponse: Codable {
    let globalPlace: GlobalPlace
    let userRelation: UserPlaceRelation?
}

// MARK: - API Response Models
struct GlobalPlaceSearchResponse: Codable {
    let success: Bool
    let data: [GlobalPlace]
    let total: Int
    let hasMore: Bool
}

struct GlobalPlaceDetailResponse: Codable {
    let success: Bool
    let data: GlobalPlaceResponse
}

struct CreateGlobalPlaceResponse: Codable {
    let success: Bool
    let data: GlobalPlace
    let created: Bool
    let message: String
}

// MARK: - Extensions for Compatibility
extension GlobalPlace {
    // Convert to legacy Place format for backwards compatibility
    func toLegacyPlace(withRelation relation: UserPlaceRelation? = nil) -> Place {
        // Convert attributed photos to simple URLs for legacy compatibility
        let legacyPhotos = photos?.map { $0.url } ?? []
        
        // Convert attributed videos to simple URLs
        let legacyVideos = videos?.map { $0.videoUrl } ?? []
        
        // Use public reviews as notes for legacy compatibility (take first review)
        let legacyNotes = publicReviews?.first?.text
        
        // Use private notes from relation if available
        let privateNotes = relation?.privateNotes
        
        return Place(
            id: id,
            name: name,
            description: nil,
            address: address,
            location: location,
            website: googleData?.website,
            phone: googleData?.phone,
            googlePlaceId: googlePlaceId,
            photos: legacyPhotos,
            videos: legacyVideos,
            category: category,
            customCategoryId: nil,
            subcategory: subcategory,
            rating: googleData?.rating,
            userRatingsTotal: googleData?.userRatingsTotal,
            notes: legacyNotes,
            privateNotes: privateNotes,
            publicNotes: legacyNotes,
            tags: relation?.tags,
            reviews: nil, // Could convert publicReviews if needed
            openingHours: googleData?.openingHours,
            priceLevel: googleData?.priceLevel,
            likes: nil,
            likesCount: nil,
            commentsCount: nil,
            circleId: relation?.circleId,
            addedBy: relation?.userId ?? "",
            addedByUser: nil,
            privacy: relation?.privacy ?? .followCirclePrivacy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isNew: false
        )
    }
    
    // Helper properties
    var hasPhotos: Bool {
        return photos?.isEmpty == false
    }
    
    var hasVideos: Bool {
        return videos?.isEmpty == false
    }
    
    var hasPublicReviews: Bool {
        return publicReviews?.isEmpty == false
    }
    
    var photoCount: Int {
        return photos?.count ?? 0
    }
    
    var videoCount: Int {
        return videos?.count ?? 0
    }
    
    var reviewCount: Int {
        return publicReviews?.count ?? 0
    }
    
    var displayCategory: String {
        if let subcategory = subcategory, !subcategory.isEmpty {
            return "\(category.displayName) - \(subcategory)"
        }
        return category.displayName
    }
    
    var qualityIndicator: PlaceQuality {
        if qualityScore >= 0.8 {
            return .excellent
        } else if qualityScore >= 0.6 {
            return .good
        } else if qualityScore >= 0.4 {
            return .fair
        } else {
            return .basic
        }
    }
    
    var completenessPercentage: Int {
        return Int(dataCompleteness * 100)
    }
}

enum PlaceQuality: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case basic = "basic"
    
    var displayName: String {
        switch self {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .basic:
            return "Basic"
        }
    }
    
    var color: UIColor {
        switch self {
        case .excellent:
            return UIColor(hex: "#10B981") // Green
        case .good:
            return UIColor(hex: "#3B82F6") // Blue
        case .fair:
            return UIColor(hex: "#F59E0B") // Orange
        case .basic:
            return UIColor(hex: "#6B7280") // Gray
        }
    }
    
    var iconName: String {
        switch self {
        case .excellent:
            return "star.fill"
        case .good:
            return "star.circle.fill"
        case .fair:
            return "star.circle"
        case .basic:
            return "star"
        }
    }
}

// MARK: - Helper Extensions
extension AttributedPhoto {
    var attribution: String {
        if let uploaderName = uploadedByName, !uploaderName.isEmpty {
            return "Photo by \(uploaderName)"
        } else {
            return "User photo"
        }
    }
}

extension AttributedVideo {
    var attribution: String {
        if let uploaderName = uploadedByName, !uploaderName.isEmpty {
            return "Video by \(uploaderName)"
        } else {
            return "User video"
        }
    }
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}

// MARK: - Map Annotation Helper
extension GlobalPlace {
    func asMapAnnotation() -> GlobalPlaceAnnotation {
        return GlobalPlaceAnnotation(globalPlace: self)
    }
    
    var coordinate: CLLocationCoordinate2D {
        if let location = location?.clLocation {
            return location.coordinate
        }
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}

// Custom map annotation class for global places
class GlobalPlaceAnnotation: NSObject, MKAnnotation {
    let globalPlace: GlobalPlace
    
    var coordinate: CLLocationCoordinate2D {
        return globalPlace.coordinate
    }
    
    var title: String? {
        return globalPlace.name
    }
    
    var subtitle: String? {
        return globalPlace.address
    }
    
    init(globalPlace: GlobalPlace) {
        self.globalPlace = globalPlace
        super.init()
    }
}