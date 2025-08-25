import Foundation

// MARK: - PlaceVideo Model
struct PlaceVideo: Codable {
    let id: String
    let userId: String
    let placeId: String
    let placeName: String
    let videoUrl: String?
    let previewUrl: String?
    let thumbnailUrl: String?
    let title: String
    let description: String
    let duration: TimeInterval? // seconds - optional for embedded videos
    let fileSize: Int64? // bytes after compression - optional for embedded videos
    let originalSize: Int64? // bytes before compression - optional for embedded videos
    let compressionRatio: Float? // optional for embedded videos
    let visibility: VideoVisibility
    let viewCount: Int
    let lastViewedAt: Date?
    var likeCount: Int
    var commentCount: Int
    let tags: [String]
    let uploadProgress: Double? // optional for embedded videos
    let uploadStatus: VideoUploadStatus
    let storageClass: StorageClass? // optional for embedded videos
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    
    // Content type and embed fields
    let contentType: String? // "photo" or "video"
    let videoType: String? // "uploaded" or "embedded"
    let embedUrl: String?
    let embedPlatform: String? // "tiktok", "instagram", "youtube", "twitter"
    let embedHtml: String?
    let embedMetadata: EmbedMetadata?
    
    // Additional properties from API
    var user: User?
    var likedByCurrentUser: Bool?
    
    // Activity-related properties
    var activityId: String?
    var activityReactionCount: Int?
    var activityCommentCount: Int?
    var userActivityReaction: String? // Emoji if user has reacted
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId
        case placeId
        case placeName
        case videoUrl
        case previewUrl
        case thumbnailUrl
        case title
        case description
        case duration
        case fileSize
        case originalSize
        case compressionRatio
        case visibility
        case viewCount
        case lastViewedAt
        case likeCount
        case commentCount
        case tags
        case uploadProgress
        case uploadStatus
        case storageClass
        case createdAt
        case updatedAt
        case deletedAt
        case user
        case contentType
        case videoType
        case embedUrl
        case embedPlatform
        case embedHtml
        case embedMetadata
        case likedByCurrentUser
        case activityId
        case activityReactionCount
        case activityCommentCount
        case userActivityReaction
    }
    
    // Helper to check if video is embedded
    var isEmbedded: Bool {
        return videoType == "embedded"
    }
}

// MARK: - Embed Metadata
struct EmbedMetadata: Codable {
    let author: String?
    let authorUrl: String?
    let providerName: String?
    let providerUrl: String?
    let width: Int?
    let height: Int?
}

// MARK: - Video Enums
enum VideoVisibility: String, Codable {
    case `public` = "public"
    case network = "network"
    case `private` = "private"
}

enum VideoUploadStatus: String, Codable {
    case uploading = "uploading"
    case processing = "processing"
    case ready = "ready"
    case failed = "failed"
    case error = "error"  // Added to match backend response
}

enum StorageClass: String, Codable {
    case standard = "standard"
    case archive = "archive"
}

// MARK: - Video Quality
enum VideoQuality {
    case preview // 480p, 0.5 Mbps (optimized for Reels)
    case full    // 720p, 1.0 Mbps (optimized for Reels)
    
    // Dynamic resolution based on orientation
    func resolution(for orientation: VideoOrientation) -> CGSize {
        switch self {
        case .preview:
            switch orientation {
            case .portrait:
                // Use 9:16 aspect ratio for portrait (TikTok style)
                return CGSize(width: 720, height: 1280)
            case .landscape:
                return CGSize(width: 1280, height: 720)
            case .square:
                return CGSize(width: 720, height: 720)
            }
        case .full:
            switch orientation {
            case .portrait:
                // Full HD portrait
                return CGSize(width: 1080, height: 1920)
            case .landscape:
                return CGSize(width: 1920, height: 1080)
            case .square:
                return CGSize(width: 1080, height: 1080)
            }
        }
    }
    
    var bitrate: Int {
        switch self {
        case .preview:
            return 500_000 // 0.5 Mbps - optimized for quick loading
        case .full:
            return 1_000_000 // 1.0 Mbps - balanced quality/size for 15s videos
        }
    }
}

enum VideoOrientation {
    case portrait
    case landscape
    case square
    
    static func from(size: CGSize) -> VideoOrientation {
        let aspectRatio = abs(size.width / size.height)
        if aspectRatio < 0.9 {
            return .portrait
        } else if aspectRatio > 1.1 {
            return .landscape
        } else {
            return .square
        }
    }
}

// MARK: - Video Quota
struct VideoQuota: Codable {
    let userId: String
    let currentMonth: String
    let videosUploaded: Int
    let totalSize: Int64
    let subscriptionTier: SubscriptionTier
    let quotaLimit: Int
    let sizeLimit: Int64
    let lastResetDate: Date
    let createdAt: Date
    let updatedAt: Date
    
    enum SubscriptionTier: String, Codable {
        case free = "free"
        case premium = "premium"
    }
}

// MARK: - API Responses
struct VideoQuotaResponse: Codable {
    let success: Bool
    let data: QuotaData
    
    struct QuotaData: Codable {
        let hasQuota: Bool
        let remainingVideos: Int
        let remainingSize: Int64
        let quotaLimit: Int
        let sizeLimit: Int64
        let videosUploaded: Int
        let totalSize: Int64
        let subscriptionTier: String
    }
}

struct VideoUploadInitResponse: Codable {
    let success: Bool
    let data: UploadData
    
    struct UploadData: Codable {
        let videoId: String
        let uploadUrls: UploadUrls
        let storagePaths: StoragePaths
    }
    
    struct UploadUrls: Codable {
        let video: String
        let preview: String
        let thumbnail: String
    }
    
    struct StoragePaths: Codable {
        let video: String
        let preview: String
        let thumbnail: String
    }
}

struct VideoResponse: Codable {
    let success: Bool
    let data: PlaceVideo
}

struct VideosResponse: Codable {
    let success: Bool
    let data: [PlaceVideo]
    let hasMore: Bool
}

// MARK: - Helper Extensions
extension PlaceVideo {
    var formattedDuration: String {
        guard let duration = duration else { return "0:00" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
    
    var formattedFileSize: String {
        guard let fileSize = fileSize else { return "N/A" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: fileSize)
    }
    
    var compressionPercentage: String {
        guard let compressionRatio = compressionRatio else { return "N/A" }
        let percentage = (1 - compressionRatio) * 100
        return String(format: "%.0f%%", percentage)
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}