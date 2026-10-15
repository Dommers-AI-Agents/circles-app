import Foundation

/// The link the home header's Share button hands out for a tab: Local or
/// Widgets. Same shape and reasoning as `WidgetShareLink` — an
/// `api.favcircles.com/app/*` universal link, so a phone with FavCircles
/// opens straight onto the tab and any other phone lands on the backend's
/// page and the App Store.
enum HomeTabShareLink {
    static let host = WidgetShareLink.host

    /// nil for a tab that has no share link (Activity, Moments).
    static func url(for segment: HomeContentSegment) -> URL? {
        guard let slug = segment.shareSlug else { return nil }
        return URL(string: "https://\(host)/app/tab/\(slug)")
    }

    /// The link's title in the share sheet and the Messages bubble.
    static func title(for segment: HomeContentSegment) -> String {
        "\(segment.title) on FavCircles"
    }
}
