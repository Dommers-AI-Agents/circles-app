import Foundation

/// What the App Clip's steps after the save finished (2026-11-24): where
/// they live, first favorites, people to follow. The clip writes it into
/// the hand-off mailbox after every step (see ClipOnboardingSummary in the
/// Circles-Clip target — keep the two in step), and the server keeps a copy
/// on the user (`clipOnboarding`). The app's first run reads it so nobody
/// is asked twice (Logic/ClipFirstRunPlan).
struct ClipOnboardingSummary: Codable, Equatable {
    enum Step: String, Codable, CaseIterable {
        case neighborhood, favorites, people
    }

    /// A zip is on the profile now (the map is centered)
    var zipcodeSet: Bool = false
    /// "Charlotte, NC", when the zip gave a city
    var city: String? = nil
    var favoritesSaved: Int = 0
    var favoriteNames: [String] = []
    var followed: Int = 0
    /// Private profiles: follow requests sent, waiting on them
    var requested: Int = 0
    /// Steps finished with their own button (not Skip)
    var completed: [Step] = []
    /// Steps they skipped: "not now", the app may ask later
    var skipped: [Step] = []
    /// The clip reached its last screen
    var finished: Bool = false

    func didComplete(_ step: Step) -> Bool { completed.contains(step) }

    private static let stashKey = "clipOnboardingSummary"

    /// Held from adoption (before the login state is read) until the first
    /// run consumes it
    static func stash(_ summary: ClipOnboardingSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: stashKey)
        }
    }

    /// The stashed summary, left in place: the first run reads it from more
    /// than one entry point (store page, generic join)
    static var stashed: ClipOnboardingSummary? {
        guard let data = UserDefaults.standard.data(forKey: stashKey) else { return nil }
        return try? JSONDecoder().decode(ClipOnboardingSummary.self, from: data)
    }

    static func clearStashed() {
        UserDefaults.standard.removeObject(forKey: stashKey)
    }
}
