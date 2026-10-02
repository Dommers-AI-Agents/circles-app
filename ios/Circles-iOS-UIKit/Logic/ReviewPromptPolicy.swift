import Foundation

/// When to ask for an App Store rating (Wes, 2026-10-02: the app never asked,
/// and 8 ratings is what holds it back in search). Pure, so the rules are
/// table-tested.
///
/// Ask only after the person has had a few good moments (saving places,
/// reaching a badge), never in their first days, at most once per app
/// version and once every 90 days. iOS adds its own cap (3 a year) and may
/// show nothing at all, so this only decides when we *may* ask.
enum ReviewPromptPolicy {
    static let minimumHappyMoments = 3
    static let minimumDaysSinceFirstSeen = 3
    static let minimumDaysBetweenAsks = 90

    struct State: Equatable {
        /// Good moments recorded on this device (places saved, badges reached).
        var happyMoments: Int
        var firstSeen: Date
        var lastAsked: Date?
        var lastAskedVersion: String?
    }

    static func shouldAsk(_ state: State, appVersion: String, now: Date) -> Bool {
        guard state.happyMoments >= minimumHappyMoments else { return false }
        guard days(from: state.firstSeen, to: now) >= minimumDaysSinceFirstSeen else { return false }
        guard state.lastAskedVersion != appVersion else { return false }
        if let lastAsked = state.lastAsked, days(from: lastAsked, to: now) < minimumDaysBetweenAsks { return false }
        return true
    }

    private static func days(from: Date, to: Date) -> Int {
        Int(to.timeIntervalSince(from) / 86_400)
    }
}
