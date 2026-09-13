import Foundation

/// A navigation stashed in UserDefaults ("pendingDeepLink") while the app
/// wasn't ready to route it — a push tap, a share, a notification action.
enum PendingLink: Equatable {
    // Single-token links
    case network
    case dailySummary
    case allPlacesMap
    case createWallet
    /// "add-place" / "me": resolved through DeepLinkRouter's open-path table.
    case openPath(String)

    // "type:payload" links
    case shareToken(circleId: String, shareToken: String)
    case circle(id: String)
    case place(id: String)
    case user(id: String)
    case share(id: String)
    case connect(fromUserId: String)
    case video(id: String)
    case notificationSettings
}

/// Turns the stored string into a `PendingLink`. Pure; SceneDelegate keeps
/// the stash/clear and the navigation. Same rules the inline parse had:
/// single tokens first, then `split(":")` (empty segments dropped) needing
/// at least two parts, `shareToken` needing three, `settings` only for
/// `settings:notifications`; anything else is nil (no navigation).
enum PendingLinkParser {
    static func parse(_ link: String) -> PendingLink? {
        switch link {
        case "network": return .network
        case "daily-summary": return .dailySummary
        case "all-places-map": return .allPlacesMap
        case "create-wallet": return .createWallet
        case "add-place", "me": return .openPath(link)
        default: break
        }

        let components = link.split(separator: ":")
        guard components.count >= 2 else { return nil }
        let type = String(components[0])
        let payload = String(components[1])

        switch type {
        case "shareToken":
            // Format: shareToken:circleId:shareToken
            guard components.count >= 3 else { return nil }
            return .shareToken(circleId: payload, shareToken: String(components[2]))
        case "circle": return .circle(id: payload)
        case "place": return .place(id: payload)
        case "user": return .user(id: payload)
        case "share": return .share(id: payload)
        case "connect": return .connect(fromUserId: payload)
        case "video": return .video(id: payload)
        case "daily-summary": return .dailySummary
        case "settings": return payload == "notifications" ? .notificationSettings : nil
        default: return nil
        }
    }
}
