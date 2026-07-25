import Foundation

/// Canonical share URLs. Every outbound share uses an https universal link on
/// api.favcircles.com: with the app installed iOS opens it directly in-app;
/// without it the backend serves a preview page with an App Store fallback.
/// Never share raw circles:// scheme links — they aren't clickable in most
/// messengers for people without the app.
enum ShareLinks {

    static let base = "https://api.favcircles.com"
    static let appStore = "https://apps.apple.com/us/app/favcircles/id6746807095"

    /// Place page link. Carries share attribution (ref) so the sharer earns
    /// reward points when the recipient adds the place.
    static func place(id: String, refUserId: String? = AuthService.shared.getUserId()) -> URL {
        var link = "\(base)/place/\(id)"
        if let refUserId = refUserId, !refUserId.isEmpty {
            link += "?ref=\(refUserId)"
        }
        return URL(string: link) ?? URL(string: base)!
    }

    /// Circle page link, optionally carrying a share token for private access
    static func circle(id: String, shareToken: String? = nil) -> URL {
        var link = "\(base)/circle/\(id)"
        if let shareToken = shareToken, !shareToken.isEmpty {
            link += "?share=\(shareToken)"
        }
        return URL(string: link) ?? URL(string: base)!
    }

    /// Connection invite link (auto-connects when opened with the app installed)
    static func connect(userId: String) -> URL {
        return URL(string: "\(base)/connect/\(userId)") ?? URL(string: base)!
    }

    static var appStoreURL: URL { URL(string: appStore)! }
}
