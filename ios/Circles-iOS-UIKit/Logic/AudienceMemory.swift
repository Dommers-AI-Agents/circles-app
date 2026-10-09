import Foundation

/// The last audience someone shared to, per screen, so the next share opens on
/// it (Wes, 2026-10-09: "remember the last selection they made so the next time
/// that is the default"). Saved only after a share SUCCEEDS, so a cancelled one
/// never moves it. Check-ins keep their own value (`CheckInAudienceChoice`),
/// because it also syncs to the account as `preferences.checkInAudience`.
///
/// Stored as "<tier>" or "<tier>:<Inner Circle list id>", where the tier is the
/// raw value of the screen's own type (`VideoVisibility`, `PrivacyTier`).
enum AudienceMemory {

    enum Surface: String {
        case moment
        case newCircle
    }

    struct Choice: Equatable {
        let tier: String
        let listId: String?
    }

    static func encode(_ choice: Choice) -> String {
        guard let listId = choice.listId, !listId.isEmpty else { return choice.tier }
        return "\(choice.tier):\(listId)"
    }

    static func decode(_ stored: String?) -> Choice? {
        guard let stored, !stored.isEmpty else { return nil }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard let tier = parts.first, !tier.isEmpty else { return nil }
        return Choice(tier: tier, listId: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
    }

    /// What to open on. A list that's gone (deleted, or everyone taken off)
    /// gives nil, and the screen uses its usual default: sharing to a list
    /// nobody is on would reach no one. `usableListIds` nil = the lists
    /// haven't loaded yet; keep the choice until they have.
    static func resolve(_ saved: Choice?, usableListIds: [String]?) -> Choice? {
        guard let saved else { return nil }
        if let listId = saved.listId, let usableListIds, !usableListIds.contains(listId) { return nil }
        return saved
    }

    // MARK: - Storage (this device, per account)

    static func key(_ surface: Surface, userId: String) -> String {
        "audienceMemory.\(surface.rawValue).\(userId)"
    }

    static func load(_ surface: Surface, userId: String?, defaults: UserDefaults = .standard) -> Choice? {
        guard let userId, !userId.isEmpty else { return nil }
        return decode(defaults.string(forKey: key(surface, userId: userId)))
    }

    static func save(_ choice: Choice, for surface: Surface, userId: String?, defaults: UserDefaults = .standard) {
        guard let userId, !userId.isEmpty else { return }
        defaults.set(encode(choice), forKey: key(surface, userId: userId))
    }
}
