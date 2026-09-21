import Foundation

/// Where an incoming URL wants the app to go. Pure data: presentation lives in
/// SceneDelegate's `route(_:)`, which switches over this.
enum DeepLinkDestination: Equatable {
    case dailySummary
    /// `promptsLogin`: the `circles://video/<id>` scheme form shows a "Login
    /// Required" alert when signed out; universal links just stash the target.
    case video(id: String, promptsLogin: Bool)
    /// `shareToken` grants view access to a private circle (`?share=`).
    case circle(id: String, shareToken: String?)
    case sharedCircle(shareId: String)
    case place(id: String, refUserId: String?)
    /// `circles://place/<id>` from the widget / share extension — the receiver
    /// also consumes the pending-open mailbox so a cold launch doesn't
    /// navigate a second time.
    case placeFromExtension(id: String)
    case userProfile(id: String)
    /// `referralCode` rides along on invite links (`?code=`); whether it is
    /// stashed depends on auth state, which the receiver checks.
    case connectionInvite(userId: String, referralCode: String?)
    case importFlow
    case allPlacesMap(focusCategory: String?)
    case notificationSettings
    case network
    case addPlace
    case meTab
    /// Rewards hub on the Piggy Bank tab (weekly summary email "See my FavCoins").
    case piggyBank
    case referral(code: String)
    case sticker(code: String)
    case upgradePaywall
    /// A shared widget link — `/app/widget/<id>` or `circles://widget/<id>`.
    /// Opens the Widgets tab on that widget's page, turning it on if the
    /// recipient had it switched off; a link to something they can't see is
    /// the one way this share is worth nothing.
    case widget(id: String)
}

/// Interprets universal links (https://api.favcircles.com/…) and the custom
/// `circles://` scheme into a `DeepLinkDestination`. Extracted from
/// SceneDelegate so every link shape the emails, QR codes, widget, share
/// extension and App Clip produce is covered by unit tests.
struct DeepLinkRouter {
    static let customScheme = "circles"
    /// Branded domain plus the legacy run.app host — old shared links must
    /// keep working.
    static let universalLinkHosts: Set<String> = [
        "api.favcircles.com",
        "circles-backend-196924649787.us-central1.run.app"
    ]

    func destination(for url: URL) -> DeepLinkDestination? {
        if url.scheme == Self.customScheme {
            return customSchemeDestination(url)
        }
        if let host = url.host, Self.universalLinkHosts.contains(host) {
            return universalLinkDestination(url)
        }
        return nil
    }

    // MARK: - Universal links

    func universalLinkDestination(_ url: URL) -> DeepLinkDestination? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return nil }

        if first == "app", parts.count >= 2 {
            switch parts[1] {
            case "daily-summary":
                return .dailySummary
            case "open":
                return query(url, "path").flatMap(openPathDestination)
            case "video":
                return parts.count >= 3 ? .video(id: parts[2], promptsLogin: false) : nil
            case "widget":
                return parts.count >= 3 ? .widget(id: parts[2]) : nil
            case "circle":
                return parts.count >= 3 ? .circle(id: parts[2], shareToken: query(url, "share")) : nil
            case "connect":
                return parts.count >= 3 ? .connectionInvite(userId: parts[2], referralCode: query(url, "code")) : nil
            case "import":
                return .importFlow
            case "map":
                return .allPlacesMap(focusCategory: query(url, "focus"))
            default:
                return nil
            }
        }

        switch first {
        case "daily-summary":
            return .dailySummary
        case "video":
            return parts.count >= 2 ? .video(id: parts[1], promptsLogin: false) : nil
        case "share":
            // https://<backend>/share/video/<id>
            return (parts.count >= 3 && parts[1] == "video") ? .video(id: parts[2], promptsLogin: false) : nil
        case "circle":
            return parts.count >= 2 ? .circle(id: parts[1], shareToken: query(url, "share")) : nil
        case "place":
            return parts.count >= 2 ? .place(id: parts[1], refUserId: query(url, "ref")) : nil
        case "user":
            return parts.count >= 2 ? .userProfile(id: parts[1]) : nil
        case "connect":
            return parts.count >= 2 ? .connectionInvite(userId: parts[1], referralCode: query(url, "code")) : nil
        case "s":
            // Physical sticker QR code: https://<backend>/s/<code>
            return parts.count >= 2 ? .sticker(code: parts[1]) : nil
        default:
            return nil
        }
    }

    /// `/app/open?path=…` targets used by email CTAs.
    func openPathDestination(_ path: String) -> DeepLinkDestination? {
        switch path {
        case "settings/notifications": return .notificationSettings
        case "network", "network/find-friends": return .network
        case "add-place": return .addPlace
        case "me": return .meTab
        // Weekly summary email "See my FavCoins" — the Piggy Bank tab
        case "create-wallet", "rewards/piggy-bank": return .piggyBank
        default: return nil
        }
    }

    // MARK: - circles:// scheme

    func customSchemeDestination(_ url: URL) -> DeepLinkDestination? {
        // Host-based forms first (circles://connect/<id>), then the
        // path-based twins (circles:///connect/<id>).
        let hostPathId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch url.host {
        case "connect" where !hostPathId.isEmpty:
            return .connectionInvite(userId: hostPathId, referralCode: query(url, "code"))
        case "video" where !hostPathId.isEmpty:
            return .video(id: hostPathId, promptsLogin: true)
        case "referral":
            if let code = query(url, "code") { return .referral(code: code) }
        case "sticker":
            if let code = query(url, "code") { return .sticker(code: code) }
        case "daily-summary":
            return .dailySummary
        case "place" where !hostPathId.isEmpty:
            return .placeFromExtension(id: hostPathId)
        case "upgrade":
            return .upgradePaywall
        case "widget" where !hostPathId.isEmpty:
            return .widget(id: hostPathId)
        case "network":
            return .network
        case "settings" where url.path == "/notifications":
            return .notificationSettings
        case "circle":
            if let token = query(url, "share") { return .circle(id: hostPathId, shareToken: token) }
            if !hostPathId.isEmpty { return .circle(id: hostPathId, shareToken: nil) }
        default:
            break
        }

        let parts = url.pathComponents   // ["/", "circle", "<id>"] for circles:///circle/<id>
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "circle" where parts.count >= 3:
            return .circle(id: parts[2], shareToken: query(url, "share"))
        case "share" where parts.count >= 4 && parts[2] == "circle":
            return .sharedCircle(shareId: parts[3])
        case "place" where parts.count >= 3:
            return .place(id: parts[2], refUserId: query(url, "ref"))
        case "user" where parts.count >= 3:
            return .userProfile(id: parts[2])
        case "widget" where parts.count >= 3:
            return .widget(id: parts[2])
        case "connect" where parts.count >= 3:
            return .connectionInvite(userId: parts[2], referralCode: query(url, "code"))
        default:
            return nil
        }
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }
}
