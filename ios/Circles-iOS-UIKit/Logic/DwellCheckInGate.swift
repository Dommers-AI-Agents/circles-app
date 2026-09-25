import Foundation

/// The rules behind the "you're at <saved place> — check in?" banner for
/// people who allow location Always.
///
/// Whether the phone is really AT the place is `ArrivalVerifier`'s question;
/// this is the budget: once per place per day, a few a day at most, never
/// two close together — and, from the second of a day, an offer to turn
/// them off, so the reminder gets people going without wearing them down.
///
/// Pure so the rules are testable; `DwellCheckInMonitor` owns the location
/// manager and the notification requests.
enum DwellCheckInGate {
    /// Never more than this many banners in a calendar day.
    static let dailyCap = 3
    /// And never two within this window, whatever the places.
    static let globalCooldown: TimeInterval = 30 * 60

    /// Region-monitoring identifier prefix; distinct from the old
    /// notification-trigger prefix so the two never clear each other.
    static let identifierPrefix = "dwell."

    static func placeId(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let id = String(identifier.dropFirst(identifierPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// Whether the feature can run at all for this person.
    static func isAvailable(isAlwaysAuthorized: Bool, notificationsAuthorized: Bool, preferenceOn: Bool) -> Bool {
        isAlwaysAuthorized && notificationsAuthorized && preferenceOn
    }

    struct EntryContext: Equatable {
        var promptedTodayForPlace: Bool
        var promptsToday: Int
        var lastFiredAt: Date?
        var now: Date
    }

    /// Asked on region entry (is a watch worth starting?) and again at the
    /// moment of arrival (is the banner still allowed?).
    static func shouldPrompt(_ c: EntryContext) -> Bool {
        if c.promptedTodayForPlace { return false }
        if c.promptsToday >= dailyCap { return false }
        if let last = c.lastFiredAt, c.now.timeIntervalSince(last) < globalCooldown { return false }
        return true
    }

    /// From the second banner of a day the notification carries a
    /// "Turn off reminders" action.
    static func offersOptOut(promptsToday: Int) -> Bool {
        promptsToday >= 1
    }
}
