import UIKit

/// Where another person sits on the follow → connect ladder.
///
/// Follow and Connect are two different things in Circles, and the backend has
/// always treated them that way: following someone puts their public activity
/// in your feed, while connecting also opens their `myNetwork`-privacy circles,
/// messaging and place suggestions. Following is one-way and instant; connecting
/// needs both people to agree.
///
/// Every list that shows people derives its buttons from this one enum, so a
/// person looks and behaves the same whether you found them in My Network,
/// Discover, or a search result.
enum RelationshipTier {
    /// No relationship in either direction.
    case stranger
    /// They follow you; you have not followed back. The warmest kind of
    /// stranger — the row's job is to offer Follow Back.
    case followsYou
    /// You follow them; they have not followed back.
    case following
    /// You follow each other. This is when Connect becomes worth offering —
    /// both people have already opted in, so it is likely to be accepted.
    case mutualFollow
    /// You have asked to connect and are waiting on them.
    case requestSent
    /// They have asked to connect and are waiting on you.
    case requestReceived
    /// Connected: network-only circles, messaging and suggestions are open.
    case connected

    init(user: User) {
        switch user.connectionStatus {
        case "connected", "accepted":
            self = .connected
            return
        case "pending":
            self = user.connectionDirection == "incoming" ? .requestReceived : .requestSent
            return
        default:
            break
        }

        let iFollow = user.isFollowing ?? false
        let theyFollow = user.followsYou ?? false

        if iFollow && theyFollow {
            self = .mutualFollow
        } else if iFollow {
            self = .following
        } else if theyFollow {
            self = .followsYou
        } else {
            self = .stranger
        }
    }
}

// MARK: - Row presentation

extension RelationshipTier {
    /// What tapping a row button means. The cell reports the intent; the list
    /// controller decides how to carry it out.
    enum Action {
        case follow
        case unfollow
        case connect
        case cancelRequest
        case accept
        case decline
        case message
        case more
    }

    struct ButtonSpec {
        let title: String
        let style: UIButton.FactoryButtonStyle
        let action: Action
        /// Renders as a compact glyph button rather than a titled pill.
        let isGlyph: Bool

        init(title: String, style: UIButton.FactoryButtonStyle, action: Action, isGlyph: Bool = false) {
            self.title = title
            self.style = style
            self.action = action
            self.isGlyph = isGlyph
        }
    }

    /// The row's main button — always exactly one, so there is never a question
    /// about what the obvious next step is.
    var primaryButton: ButtonSpec {
        switch self {
        case .stranger:
            return ButtonSpec(title: "Follow", style: .primary, action: .follow)
        case .followsYou:
            return ButtonSpec(title: "Follow Back", style: .primary, action: .follow)
        case .following:
            // Connect is the next rung once you already follow someone.
            // Unfollow moves to the ⋯ menu — it's the rare, destructive path.
            return ButtonSpec(title: "Connect", style: .secondary, action: .connect)
        case .mutualFollow:
            // Both people opted in, so Connect gets the strong style here.
            return ButtonSpec(title: "Connect", style: .primary, action: .connect)
        case .requestSent:
            return ButtonSpec(title: "Requested", style: .following, action: .cancelRequest)
        case .requestReceived:
            return ButtonSpec(title: "Accept", style: .primary, action: .accept)
        case .connected:
            return ButtonSpec(title: "Message", style: .secondary, action: .message)
        }
    }

    /// The optional second button. On following rows it's the ⋯ menu
    /// (View Profile / Unfollow) — Connect moved up to the primary slot.
    var secondaryButton: ButtonSpec? {
        switch self {
        case .stranger, .followsYou:
            return nil
        case .following, .mutualFollow:
            return ButtonSpec(title: "ellipsis", style: .following, action: .more, isGlyph: true)
        case .requestSent:
            return ButtonSpec(title: "ellipsis", style: .following, action: .more, isGlyph: true)
        case .requestReceived:
            return ButtonSpec(title: "xmark", style: .following, action: .decline, isGlyph: true)
        case .connected:
            return ButtonSpec(title: "ellipsis", style: .following, action: .more, isGlyph: true)
        }
    }

    /// Destructive options that used to sit as a permanently visible red button
    /// on every row. They belong in a menu, not in the scan path.
    var menuActions: [Action] {
        switch self {
        case .following, .mutualFollow:
            return [.unfollow]
        case .requestSent:
            return [.cancelRequest]
        case .connected:
            return [.unfollow, .decline]
        case .stranger, .followsYou, .requestReceived:
            return []
        }
    }
}

// MARK: - Subtitle

extension RelationshipTier {
    /// The one line under a person's name. In a recommendation network the
    /// thing worth knowing about someone is what they have saved and how you
    /// already overlap — not their email address.
    ///
    /// Falls back through location and bio so a sparse profile never renders an
    /// empty row.
    func subtitle(for user: User) -> String {
        var parts: [String] = []

        // Lead with the reason this person is worth your attention.
        if self == .followsYou || ((self == .mutualFollow || self == .requestReceived) && (user.followsYou ?? false)) {
            parts.append("Follows you")
        } else if let mutual = user.mutualConnectionsCount, mutual > 0 {
            parts.append("\(mutual) mutual")
        } else if let names = user.mutualConnectionNames, let first = names.first {
            parts.append(names.count > 1 ? "Known by \(first) +\(names.count - 1)" : "Known by \(first)")
        } else if let distance = user.distance, distance > 0 {
            parts.append(distance < 1
                ? "Nearby"
                : String(format: "%.0f km away", distance))
        }

        if let places = user.placesCount, places > 0 {
            parts.append("\(places) \(places == 1 ? "place" : "places")")
        }
        if let circles = user.circlesCount, circles > 0, parts.count < 2 {
            parts.append("\(circles) \(circles == 1 ? "circle" : "circles")")
        }

        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }

        // Nothing quantitative to say — fall back to whatever the profile has.
        if let location = user.location, !location.isEmpty { return location }
        if let bio = user.bio, !bio.isEmpty { return bio }
        return "Circles member"
    }
}
