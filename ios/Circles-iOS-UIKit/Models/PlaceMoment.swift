import Foundation
import UIKit

// MARK: - PlaceMoment Model
struct PlaceMoment: Codable {
    let id: String
    let userId: String
    let placeId: String
    let placeName: String
    let title: String
    let description: String
    let contentType: MomentContentType
    let visibility: MomentVisibility
    let tags: [String]
    
    // Media URLs (for uploaded content)
    let mediaUrls: [String]? // Array for carousel support
    let thumbnailUrl: String?
    
    // Video specific (for uploaded videos)
    let videoUrl: String?
    let previewUrl: String?
    let duration: TimeInterval? // Max 15 seconds
    
    // Embedded content fields
    let embedUrl: String?
    let embedPlatform: String? // tiktok, instagram, youtube, twitter
    let embedHtml: String?
    let embedMetadata: EmbedMetadata?
    
    // Compression tracking
    let fileSize: Int64? // bytes after compression
    let originalSize: Int64? // bytes before compression
    let compressionRatio: Float?
    
    // Engagement metrics
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let lastViewedAt: Date?
    
    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    
    // User info (populated from API)
    var user: User?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId
        case placeId
        case placeName
        case title
        case description
        case contentType
        case visibility
        case tags
        case mediaUrls
        case thumbnailUrl
        case videoUrl
        case previewUrl
        case duration
        case embedUrl
        case embedPlatform
        case embedHtml
        case embedMetadata
        case fileSize
        case originalSize
        case compressionRatio
        case viewCount
        case likeCount
        case commentCount
        case shareCount
        case lastViewedAt
        case createdAt
        case updatedAt
        case deletedAt
        case user
    }
}

// MARK: - Content Type
enum MomentContentType: String, Codable {
    case videoUploaded = "video_uploaded"
    case videoEmbedded = "video_embedded"
    case photo = "photo"
    case carousel = "carousel"
    
    var displayName: String {
        switch self {
        case .videoUploaded: return "Video"
        case .videoEmbedded: return "Linked Video"
        case .photo: return "Photo"
        case .carousel: return "Photos"
        }
    }
    
    var icon: String {
        switch self {
        case .videoUploaded: return "video.fill"
        case .videoEmbedded: return "link.circle.fill"
        case .photo: return "photo.fill"
        case .carousel: return "photo.on.rectangle.angled"
        }
    }
}

// MARK: - Visibility
enum MomentVisibility: String, Codable {
    case `public` = "public"
    case network = "network"
    case `private` = "private"
}

// MARK: - Content Limits
struct MomentLimits {
    static let videoDuration: TimeInterval = 15.0 // seconds
    static let videoMaxSize: Int64 = 2 * 1024 * 1024 // 2MB
    static let photoMaxSize: Int64 = 300 * 1024 // 300KB
    static let carouselMaxPhotos = 5
    static let carouselMaxTotalSize: Int64 = 1_500_000 // 1.5MB
    
    // Compression settings
    static let videoResolution = CGSize(width: 1280, height: 720) // 720p
    static let videoBitrate = 500_000 // 500 Kbps
    static let photoMaxDimension: CGFloat = 1080
    static let photoCompressionQuality: CGFloat = 0.7
}

// MARK: - Helper Extensions
extension PlaceMoment {
    // Check if content is embedded (no storage cost)
    var isEmbedded: Bool {
        return contentType == MomentContentType.videoEmbedded
    }
    
    // Check if content is a video (uploaded or embedded)
    var isVideo: Bool {
        return contentType == MomentContentType.videoUploaded || contentType == MomentContentType.videoEmbedded
    }
    
    // Get primary media URL
    var primaryMediaUrl: String? {
        if contentType == MomentContentType.videoEmbedded {
            return embedUrl
        } else if contentType == MomentContentType.videoUploaded {
            return videoUrl
        } else {
            return mediaUrls?.first
        }
    }
    
    // Format file size for display
    var formattedFileSize: String {
        guard let fileSize = fileSize else { return "N/A" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: fileSize)
    }
    
    // Format compression percentage
    var compressionPercentage: String {
        guard let compressionRatio = compressionRatio else { return "N/A" }
        let percentage = compressionRatio * 100
        return String(format: "%.0f%%", percentage)
    }
    
    // Format duration for videos
    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
    
    // Format engagement counts
    var formattedViewCount: String {
        return formatCount(viewCount)
    }
    
    var formattedLikeCount: String {
        return formatCount(likeCount)
    }
    
    var formattedCommentCount: String {
        return formatCount(commentCount)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    
    // Time ago formatting
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

// MARK: - Migration Helper
extension PlaceMoment {
    // Convert from old PlaceVideo model
    init(from video: PlaceVideo) {
        self.id = video.id
        self.userId = video.userId
        self.placeId = video.placeId
        self.placeName = video.placeName
        self.title = video.title
        self.description = video.description
        self.contentType = video.isEmbedded ? MomentContentType.videoEmbedded : MomentContentType.videoUploaded
        self.visibility = MomentVisibility(rawValue: video.visibility.rawValue) ?? .public
        self.tags = video.tags
        
        self.mediaUrls = video.videoUrl != nil ? [video.videoUrl!] : nil
        self.thumbnailUrl = video.thumbnailUrl
        self.videoUrl = video.videoUrl
        self.previewUrl = video.previewUrl
        self.duration = video.duration
        
        self.embedUrl = video.embedUrl
        self.embedPlatform = video.embedPlatform
        self.embedHtml = video.embedHtml
        self.embedMetadata = video.embedMetadata
        
        self.fileSize = video.fileSize
        self.originalSize = video.originalSize
        self.compressionRatio = video.compressionRatio
        
        self.viewCount = video.viewCount
        self.likeCount = video.likeCount
        self.commentCount = video.commentCount
        self.shareCount = 0 // New field
        self.lastViewedAt = video.lastViewedAt
        
        self.createdAt = video.createdAt
        self.updatedAt = video.updatedAt
        self.deletedAt = video.deletedAt
        
        self.user = video.user
    }
}

// MARK: - API Responses
struct MomentResponse: Codable {
    let success: Bool
    let data: PlaceMoment
}

struct MomentsResponse: Codable {
    let success: Bool
    let data: [PlaceMoment]
    let hasMore: Bool
}

struct MomentUploadResponse: Codable {
    let success: Bool
    let data: UploadData
    
    struct UploadData: Codable {
        let momentId: String
        let uploadUrls: [String]
        let thumbnailUploadUrl: String?
    }
}