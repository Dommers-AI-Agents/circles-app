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
    let likeCount: Int
    let commentCount: Int
    let tags: [String]
    let uploadProgress: Double? // optional for embedded videos
    let uploadStatus: VideoUploadStatus
    let storageClass: StorageClass? // optional for embedded videos
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    
    // Embedded video fields
    let videoType: String? // "uploaded" or "embedded"
    let embedUrl: String?
    let embedPlatform: String? // "tiktok", "instagram", "youtube", "twitter"
    let embedHtml: String?
    let embedMetadata: EmbedMetadata?
    
    // Additional properties from API
    var user: User?
    
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
        case videoType
        case embedUrl
        case embedPlatform
        case embedHtml
        case embedMetadata
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
}

enum StorageClass: String, Codable {
    case standard = "standard"
    case archive = "archive"
}

// MARK: - Video Quality
enum VideoQuality {
    case preview // 480p, 0.5 Mbps (optimized for Reels)
    case full    // 720p, 1.0 Mbps (optimized for Reels)
    
    var resolution: CGSize {
        switch self {
        case .preview:
            return CGSize(width: 854, height: 480)
        case .full:
            return CGSize(width: 1280, height: 720)
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