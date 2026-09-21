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
    /// "quote:<id>": the Quotes page opened on that quote in the reel
    case quote(id: String)
    /// "widget:<id>": the Widgets segment with one widget's page open
    /// (the "Send a Postcard" quick action).
    case widget(id: String)
    /// "postcard-order:<orderId>": the postcard page open on one printed
    /// card's status (its "printing" push tapped on a cold start).
    case postcardOrder(id: String)

    // "type:payload" links
    case shareToken(circleId: String, shareToken: String)
    case circle(id: String)
    case place(id: String)
    case user(id: String)
    case share(id: String)
    case connect(fromUserId: String)
    case video(id: String)
    case notificationSettings
    /// "check-in:<placeId>": the "you're near <saved place>" banner tapped on a cold start,
    /// or a "Check in at <place>" Home Screen quick action.
    case checkIn(placeId: String)
    /// "check-in": the static "Check In" Home Screen quick action; the sheet
    /// opens with its place picker.
    case quickCheckIn
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
        case "check-in": return .quickCheckIn
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
        case "widget": return .widget(id: payload)
        case "quote": return .quote(id: payload)
        case "postcard-order": return .postcardOrder(id: payload)
        case "video": return .video(id: payload)
        case "daily-summary": return .dailySummary
        case "check-in": return .checkIn(placeId: payload)
        case "settings": return payload == "notifications" ? .notificationSettings : nil
        default: return nil
        }
    }
}
