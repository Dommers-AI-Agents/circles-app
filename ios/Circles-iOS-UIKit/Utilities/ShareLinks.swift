import Foundation

/// Canonical share URLs. Every outbound share uses an https universal link on
/// api.favcircles.com: with the app installed iOS opens it directly in-app;
/// without it the backend serves a preview page with an App Store fallback.
/// Never share raw circles:// scheme links — they aren't clickable in most
/// messengers for people without the app.
enum ShareLinks {

    static let base = "https://api.favcircles.com"
    /// A store's public ordering page lives on its own host so the app never
    /// intercepts it (no universal link there): the store's website links it
    static let orderBase = "https://order.favcircles.com"
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

    /// Public profile link (opens the profile in-app when installed)
    static func user(id: String) -> URL {
        return URL(string: "\(base)/user/\(id)") ?? URL(string: base)!
    }

    /// The store's ordering page, order.favcircles.com/<slug>
    static func orderPage(slug: String) -> URL {
        return URL(string: "\(orderBase)/\(slug)") ?? URL(string: orderBase)!
    }

    /// The server's App Store link (ClientConfigService), the built-in one offline
    static var appStoreURL: URL {
        URL(string: ClientConfigService.shared.config.appStoreUrl) ?? URL(string: appStore)!
    }
}
