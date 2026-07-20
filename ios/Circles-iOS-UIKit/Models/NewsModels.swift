import Foundation

// Models for the home-page News tab. Articles come pre-parsed and merged from
// the backend (publisher RSS feeds); the app never touches raw XML.

struct NewsArticle: Codable {
    let id: String
    let title: String
    let link: String
    let sourceId: String
    let sourceName: String
    let pubDate: Date
    let thumbnailUrl: String?
    let snippet: String?

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: pubDate, relativeTo: Date())
    }
}

struct NewsSource: Codable {
    let id: String
    let displayName: String
    let category: String?
    let homepage: String?
    let color: String?
}

struct NewsFeedResponse: Codable {
    let success: Bool
    let articles: [NewsArticle]
    let sourcesFailed: [String]?
    let configured: Bool
}

struct NewsSourcesResponse: Codable {
    let success: Bool
    let sources: [NewsSource]
    // nil = user never configured the feature (show first-run picker);
    // [] = explicitly chose none
    let enabledSourceIds: [String]?
}
