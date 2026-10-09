import Foundation

/// The check-in screen's "Who's it for?" choice, and the remembered one (the last check-in's, since 2026-10-09)
/// (Wes, 2026-10-08: "I want mine to be inner circle by default. Not
/// connections"). Stored on the account as `preferences.checkInAudience`:
/// "everyone", "connections", "justMe" or "list:<Inner Circle list id>".
enum CheckInAudienceChoice: Equatable {
    case justMe, connections, everyone, list(String)

    var storedValue: String {
        switch self {
        case .justMe: return "justMe"
        case .connections: return "connections"
        case .everyone: return "everyone"
        case .list(let id): return "list:\(id)"
        }
    }

    init?(storedValue: String?) {
        guard let value = storedValue else { return nil }
        switch value {
        case "justMe": self = .justMe
        case "connections": self = .connections
        case "everyone": self = .everyone
        default:
            guard value.hasPrefix("list:"), value.count > 5 else { return nil }
            self = .list(String(value.dropFirst(5)))
        }
    }

    /// What the screen opens on: the saved default, unless it names a list
    /// that's gone (deleted, or everyone removed) — then My connections.
    /// `listIds` nil = lists not loaded yet; keep the default for now.
    static func initial(saved: String?, listIds: [String]?) -> CheckInAudienceChoice {
        guard let choice = CheckInAudienceChoice(storedValue: saved) else { return .connections }
        if case .list(let id) = choice, let listIds, !listIds.contains(id) { return .connections }
        return choice
    }
}
