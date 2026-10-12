import Foundation

/// Which cards the My Network → Discover page shows, in order. Places and
/// the board hide when empty; people and the invite always show.
enum NetworkDiscoverLayout {

    enum Card: Equatable {
        case lovedPlaces
        case leaderboard
        case people
        case invite
    }

    static func cards(lovedPlaces: Int, boardRows: Int, people: Int) -> [Card] {
        var out: [Card] = []
        if lovedPlaces > 0 { out.append(.lovedPlaces) }
        // A board of just you isn't a leaderboard
        if boardRows > 1 { out.append(.leaderboard) }
        // Always: with no fresh suggestions it still offers See all — the
        // way to browse everyone you haven't connected with yet
        out.append(.people)
        out.append(.invite)
        return out
    }

    /// People lists in priority order, each person kept once (first wins),
    /// minus anyone you're already connected to or have already asked —
    /// "might know" means someone you can still Follow or Connect with
    static func mergePeople(_ lists: [[User]]) -> [User] {
        var seen = Set<String>()
        return lists.flatMap { $0 }
            .filter { !["accepted", "connected", "pending"].contains(($0.connectionStatus ?? "").lowercased()) }
            .filter { seen.insert($0.id).inserted }
    }

    /// What the button on a person's row or card does. Follow is one-way;
    /// Connect is the "I know them" step, offered once you follow someone
    /// (LinkedIn's split; Wes, 2026-10-12). Connected and a sent request are
    /// states, not actions.
    enum PersonAction: Equatable {
        case follow
        case connect
        case requestSent
        case connected
    }

    static func action(for user: User) -> PersonAction {
        switch (user.connectionStatus ?? "none").lowercased() {
        case "accepted", "connected": return .connected
        case "pending": return .requestSent
        default: return user.isFollowing == true ? .connect : .follow
        }
    }

    /// "Saved by Brit, Sal + 3"
    static func savedByLine(names: [String], total: Int) -> String {
        let shown = names.prefix(2)
        let rest = total - shown.count
        guard !shown.isEmpty else { return "Saved by \(total) people" }
        return "Saved by " + shown.joined(separator: ", ") + (rest > 0 ? " + \(rest)" : "")
    }

    /// The one-line reason under a suggested person
    static func reason(for user: User) -> String {
        if let reason = user.suggestionReason, !reason.isEmpty { return reason }
        if let km = user.distance {
            let miles = km * 0.621371
            return miles < 1 ? "📍 Near you" : "📍 \(Int(miles.rounded())) mi away"
        }
        if user.followsYou == true || user.discoveryType == "followsYou" { return "👋 Follows you" }
        if let mutual = user.mutualConnectionNames?.first { return "Knows \(mutual)" }
        return "On FavCircles"
    }

    /// "You're 2nd of 48 · 8 behind first"
    static func standingLine(rank: Int?, contributors: Int, behindFirst: Int?) -> String? {
        guard let rank else { return nil }
        var line = "You're \(MilestoneCopy.ordinal(rank)) of \(contributors)"
        if let behind = behindFirst { line += behind == 0 ? " · leading" : " · \(behind) behind first" }
        return line
    }
}
