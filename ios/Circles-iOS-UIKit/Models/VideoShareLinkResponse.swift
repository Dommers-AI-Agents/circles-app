import Foundation

// MARK: - Video Share Link Response
struct VideoShareLinkResponse: Codable {
    let success: Bool
    let data: VideoShareData
}

struct VideoShareData: Codable {
    let shareUrl: String
    let deepLink: String
    let shareText: String
    let videoTitle: String?
    let placeName: String?
    let thumbnailUrl: String?
}