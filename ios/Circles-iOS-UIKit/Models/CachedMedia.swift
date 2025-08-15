import Foundation

// MARK: - CachedMedia Model
struct CachedMedia: Codable {
    let id: String
    let url: String
    let localPath: String
    let mediaType: MediaType
    let userId: String?
    let fileSize: Int64
    let cachedAt: Date
    let lastAccessedAt: Date
    let expiresAt: Date?
    let isPermanent: Bool // True for user's own content
    
    enum MediaType: String, Codable {
        case image = "image"
        case video = "video"
        case thumbnail = "thumbnail"
        case videoPreview = "video_preview"
    }
    
    // Check if cache is expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    // Update last accessed time
    mutating func markAccessed() {
        self = CachedMedia(
            id: id,
            url: url,
            localPath: localPath,
            mediaType: mediaType,
            userId: userId,
            fileSize: fileSize,
            cachedAt: cachedAt,
            lastAccessedAt: Date(),
            expiresAt: expiresAt,
            isPermanent: isPermanent
        )
    }
}

// MARK: - Cache Metadata
struct CacheMetadata: Codable {
    let totalSize: Int64
    let itemCount: Int
    let lastCleanup: Date
    let userContentSize: Int64
    let networkContentSize: Int64
    
    static var empty: CacheMetadata {
        return CacheMetadata(
            totalSize: 0,
            itemCount: 0,
            lastCleanup: Date(),
            userContentSize: 0,
            networkContentSize: 0
        )
    }
}