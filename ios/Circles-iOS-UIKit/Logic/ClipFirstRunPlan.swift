import Foundation

/// Which of the app's first-run screens the App Clip already took care of
/// (2026-11-24). The rule: skip only what the clip COMPLETED. A Skip in the
/// clip means "not now", and the app may ask on its own screen. Pure; no
/// UIKit, no services.
struct ClipFirstRunPlan: Equatable {
    /// "Your place, your people" (store path) and "What's your favorite
    /// place?" (generic path): the clip's favorites step finished with saves
    let skipsFirstFavorite: Bool
    /// The people screens ("Your place, your people", "Explore other
    /// people's maps"): the clip's people step finished, follows or not
    let skipsPeople: Bool
    /// "More places like <favorite>": they already added favorites in the clip
    let skipsMorePlaces: Bool

    static let none = ClipFirstRunPlan(skipsFirstFavorite: false, skipsPeople: false, skipsMorePlaces: false)

    init(skipsFirstFavorite: Bool, skipsPeople: Bool, skipsMorePlaces: Bool) {
        self.skipsFirstFavorite = skipsFirstFavorite
        self.skipsPeople = skipsPeople
        self.skipsMorePlaces = skipsMorePlaces
    }

    init(summary: ClipOnboardingSummary?) {
        guard let summary else { self = .none; return }
        let favoritesDone = summary.didComplete(.favorites) && summary.favoritesSaved > 0
        skipsFirstFavorite = favoritesDone
        skipsPeople = summary.didComplete(.people)
        skipsMorePlaces = summary.favoritesSaved > 0
    }

    /// Anything to skip at all
    var isEmpty: Bool { self == .none }
}
