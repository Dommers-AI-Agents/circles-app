import Foundation
import CoreLocation
import MapKit

// MARK: - Global Place Model
struct GlobalPlace: Codable, Identifiable {
    let id: String
    let googlePlaceId: String?
    let deduplicationKey: String?
    let legacyPlaceIds: [String]?
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
        case googlePlaceId, deduplicationKey, legacyPlaceIds, name, address, location, category, subcategory
        case photos, videos, publicReviews, userContributions, googleData
        case totalCircleReferences, totalUserReferences, lastActivityAt
        case dataCompleteness, qualityScore
        case createdAt, updatedAt, deletedAt
    }
}

// MARK: - Attributed Media
struct AttributedPhoto: Codable, Identifiable {
    let id = UUID()
    /// Server-side photo id — needed for like/delete calls on this photo
    let photoId: String?
    let url: String
    // Nil for inherited legacy/Google photos — the backend intentionally
    // leaves those unattributed (no one provably took them)
    let uploadedBy: String?
    let uploadedByName: String?
    let uploadedAt: Date
    let source: MediaSource
    let width: Int?
    let height: Int?
    let fileSize: Int64?
    let likes: [String]?
    let likesCount: Int?

    enum CodingKeys: String, CodingKey {
        case photoId = "id"
        case url, uploadedBy, uploadedByName, uploadedAt, source
        case width, height, fileSize, likes, likesCount
    }
}

struct AttributedVideo: Codable, Identifiable {
    let id = UUID()
    let videoUrl: String
    let thumbnailUrl: String?
    let previewUrl: String?
    // Nil for inherited legacy videos whose owner is unknown (same contract
    // as AttributedPhoto.uploadedBy)
    let uploadedBy: String?
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
    case legacyMigration = "legacy_migration"
    case legacyImport = "legacy_import"
    case unknown

    // A source string this build doesn't recognize must never fail the whole
    // place decode — fall back to .unknown (this is how "legacy_import" broke
    // every legacy-photo place before this case existed)
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaSource(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .userUpload:
            return "User Upload"
        case .googlePlaces:
            return "Google Places"
        case .legacyMigration:
            return "Legacy Migration"
        case .legacyImport:
            return "Legacy Import"
        case .unknown:
            return "Unknown"
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

// Result of the "do we already know this venue?" pre-Google check
struct KnownPlaceMatch: Codable {
    let globalPlaceId: String
    let googlePlaceId: String?
    let name: String
    let address: String?
    let category: String?
    let photos: [String]
}

struct KnownPlaceMatchResponse: Codable {
    let success: Bool
    let data: KnownPlaceMatchData
}

struct KnownPlaceMatchData: Codable {
    let match: KnownPlaceMatch?
}

struct CreateGlobalPlaceResponse: Codable {
    let success: Bool
    let data: GlobalPlace
    let created: Bool
    let message: String
}

// MARK: - User Upload Models
struct UserUploadedPhoto: Codable, Identifiable {
    let id: String
    let imageUrl: String
    let placeName: String
    let placeId: String
    let uploadedAt: Date
    let width: Int?
    let height: Int?
    let fileSize: Int64?
    
    // Place context for navigation
    let placeAddress: String?
    let placeCategory: PlaceCategory
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case imageUrl = "url"
        case placeName = "place_name"
        case placeId = "place_id"
        case uploadedAt = "uploaded_at"
        case width, height, fileSize = "file_size"
        case placeAddress = "place_address"
        case placeCategory = "place_category"
    }
}

struct UserUploadsResponse: Codable {
    let success: Bool
    let data: [UserUploadedPhoto]
    let total: Int
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case success, data, total
        case hasMore = "has_more"
    }
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
        
        // Use private notes from relation if available, fallback to public review
        let privateNotes = relation?.privateNotes
        
        // Map description from first public review text
        let description = publicReviews?.first?.text
        
        // Debug logging to track conversion process
        print("🔍 [GlobalPlace.toLegacyPlace] Converting GlobalPlace ID: \(id)")
        print("🔍 [GlobalPlace.toLegacyPlace] Name: \(name)")
        print("🔍 [GlobalPlace.toLegacyPlace] PublicReviews count: \(publicReviews?.count ?? 0)")
        print("🔍 [GlobalPlace.toLegacyPlace] Description: \(description ?? "nil")")
        if let firstReview = publicReviews?.first {
            print("🔍 [GlobalPlace.toLegacyPlace] First review text: \(firstReview.text)")
            print("🔍 [GlobalPlace.toLegacyPlace] First review likes count: \(firstReview.likesCount)")
        }
        print("🔍 [GlobalPlace.toLegacyPlace] UserContributions totalReviews: \(userContributions.totalReviews)")
        
        // Convert PublicReview array to PlaceReview array for legacy compatibility
        let legacyReviews: [PlaceReview]? = publicReviews?.map { review in
            PlaceReview(
                id: UUID().uuidString,
                user: review.userId,
                rating: review.rating ?? 0.0,
                comment: review.text,
                date: review.createdAt
            )
        }
        
        // Aggregate likes from all public reviews
        let aggregatedLikes = publicReviews?.flatMap { $0.likes } ?? []
        let uniqueLikes = Array(Set(aggregatedLikes)) // Remove duplicates
        
        // Sum likes count from all public reviews
        let totalLikesCount = publicReviews?.reduce(0) { $0 + $1.likesCount } ?? 0
        
        // Use userContributions for comments count
        let commentsCount = userContributions.totalReviews
        
        return Place(
            id: id,
            name: name,
            description: description,
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
            reviews: legacyReviews,
            openingHours: googleData?.openingHours,
            priceLevel: googleData?.priceLevel,
            likes: uniqueLikes.isEmpty ? nil : uniqueLikes,
            likesCount: totalLikesCount > 0 ? totalLikesCount : nil,
            commentsCount: commentsCount > 0 ? commentsCount : nil,
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