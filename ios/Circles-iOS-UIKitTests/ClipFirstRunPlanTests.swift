import Testing
import Foundation
@testable import Circles_iOS

/// The App Clip's steps after the save decide which first-run screens the
/// app skips (2026-11-24): only what the clip completed, never a "not now".
struct ClipFirstRunPlanTests {
    private func summary(completed: [ClipOnboardingSummary.Step] = [], skipped: [ClipOnboardingSummary.Step] = [],
                         favorites: Int = 0, followed: Int = 0) -> ClipOnboardingSummary {
        var s = ClipOnboardingSummary()
        s.completed = completed
        s.skipped = skipped
        s.favoritesSaved = favorites
        s.favoriteNames = (0..<favorites).map { "Place \($0)" }
        s.followed = followed
        return s
    }

    @Test func noSummaryMeansTheUsualFirstRun() {
        #expect(ClipFirstRunPlan(summary: nil) == .none)
        #expect(ClipFirstRunPlan(summary: nil).isEmpty)
    }

    @Test func skippingEverythingInTheClipChangesNothingInTheApp() {
        let plan = ClipFirstRunPlan(summary: summary(skipped: [.neighborhood, .favorites, .people]))
        #expect(plan == .none)
    }

    @Test func favoritesSavedSkipTheFavoriteAndMorePlacesScreens() {
        let plan = ClipFirstRunPlan(summary: summary(completed: [.favorites], favorites: 2))
        #expect(plan.skipsFirstFavorite)
        #expect(plan.skipsMorePlaces)
        #expect(!plan.skipsPeople)
    }

    @Test func aFinishedPeopleStepSkipsThePeopleScreensEvenWithNoFollows() {
        let plan = ClipFirstRunPlan(summary: summary(completed: [.people], followed: 0))
        #expect(plan.skipsPeople)
        #expect(!plan.skipsFirstFavorite)
        #expect(!plan.skipsMorePlaces)
    }

    @Test func aCompletedFavoritesStepWithNothingSavedStillAsks() {
        // Can't happen from the clip's button (it needs a pick), but a stale
        // or hand-made summary must not hide the screen
        let plan = ClipFirstRunPlan(summary: summary(completed: [.favorites], favorites: 0))
        #expect(!plan.skipsFirstFavorite)
        #expect(!plan.skipsMorePlaces)
    }

    @Test func theSummaryRoundTripsThroughTheStash() {
        var s = summary(completed: [.neighborhood, .people], skipped: [.favorites], followed: 2)
        s.zipcodeSet = true
        s.city = "Charlotte, NC"
        s.requested = 1
        s.finished = true
        ClipOnboardingSummary.stash(s)
        #expect(ClipOnboardingSummary.stashed == s)
        // Reading leaves it in place for the next entry point
        #expect(ClipOnboardingSummary.stashed == s)
        ClipOnboardingSummary.clearStashed()
        #expect(ClipOnboardingSummary.stashed == nil)
    }

    @Test func theClipsJSONDecodes() throws {
        // The shape the Circles-Clip target writes into the mailbox
        let json = """
        {"zipcodeSet":true,"city":"Charlotte, NC","favoritesSaved":3,"favoriteNames":["A","B","C"],
         "followed":1,"requested":1,"completed":["neighborhood","favorites","people"],"skipped":[],"finished":true}
        """
        let s = try JSONDecoder().decode(ClipOnboardingSummary.self, from: Data(json.utf8))
        #expect(s.favoritesSaved == 3)
        #expect(s.completed == [.neighborhood, .favorites, .people])
        let plan = ClipFirstRunPlan(summary: s)
        #expect(plan == ClipFirstRunPlan(skipsFirstFavorite: true, skipsPeople: true, skipsMorePlaces: true))
    }
}
