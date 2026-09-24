import Foundation

/// The rules behind the "you're at <saved place> — check in?" banner for
/// people who allow location Always.
///
/// The old banner fired the moment the phone crossed into a 100 m circle,
/// which on a road of saved places is a burst of buzzes. This one arms a
/// timer on entry and fires only if the phone is STILL in the circle
/// `dwellSeconds` later — leaving cancels it. Five minutes inside a 100 m
/// circle is a stop, not a drive-by.
///
/// Pure so the rules are testable; `DwellCheckInMonitor` owns the location
/// manager and the notification requests.
enum DwellCheckInGate {
    /// How long the phone must stay inside the region before the banner fires.
    static let dwellSeconds: TimeInterval = 5 * 60
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
        var lastArmedAt: Date?
        var now: Date
    }

    /// On region entry: arm the dwell timer, or stay quiet.
    static func shouldArm(_ c: EntryContext) -> Bool {
        if c.promptedTodayForPlace { return false }
        if c.promptsToday >= dailyCap { return false }
        if let last = c.lastArmedAt, c.now.timeIntervalSince(last) < globalCooldown { return false }
        return true
    }
}
