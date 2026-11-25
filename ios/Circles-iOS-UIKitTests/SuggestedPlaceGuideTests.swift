import Testing
import Foundation
@testable import Circles_iOS

/// "Wesley suggested Cinergy for you" opens the place and walks a new user
/// through it, with Skip as the way out (Wes, 2026-11-25).
struct SuggestedPlaceGuideTests {

    @Test func someoneNewIsWalkedThroughAndEveryoneElseJustLands() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let policy = SuggestedPlaceGuidePolicy.self
        // Still in the tour, whatever the account's age
        #expect(policy.shouldGuide(tutorialPending: true, accountCreated: nil, now: now))
        // Tour done, first week: the welcome suggestion still explains itself
        #expect(policy.shouldGuide(tutorialPending: false, accountCreated: now.addingTimeInterval(-3600), now: now))
        #expect(policy.shouldGuide(tutorialPending: false, accountCreated: now.addingTimeInterval(-6 * 86400), now: now))
        // A settled account gets the place and nothing over it
        #expect(!policy.shouldGuide(tutorialPending: false, accountCreated: now.addingTimeInterval(-8 * 86400), now: now))
        #expect(!policy.shouldGuide(tutorialPending: false, accountCreated: nil, now: now))
    }

    @Test func theWalkthroughSaysWhoSuggestedItThenSaveThenGettingThere() {
        let stops = ScreenGuideCopy.stops(.suggestedPlace, placeName: "Cinergy Dine-In", fromName: "Wesley Sgroi")
        #expect(stops.count == 3)
        #expect(stops[0].title == "Wesley suggested Cinergy Dine-In")
        #expect(stops[0].message.contains("place page"))
        #expect(stops[1].title == "Save it")
        #expect(stops[1].message.contains("Cinergy Dine-In"))
        #expect(stops[1].message.contains("a list of your places"))
        #expect(stops[2].title.contains("Directions"))
    }

    @Test func withoutANameItStillSaysItWasSuggested() {
        #expect(ScreenGuideCopy.stops(.suggestedPlace, placeName: "Cinergy").first?.title == "Suggested for you: Cinergy")
        #expect(ScreenGuideCopy.stops(.suggestedPlace, placeName: "Cinergy", fromName: "  ").first?.title == "Suggested for you: Cinergy")
        #expect(ScreenGuideCopy.stops(.suggestedPlace).count == 3)
    }

    @Test func itEndsByOfferingAPlaceOfTheirOwnOrTheTour() {
        let finish = ScreenGuideCopy.finish(.suggestedPlace)
        #expect(finish.title == "Now one of your own")
        #expect(finish.next == ScreenGuideCopy.addPlaceNext)
        #expect(finish.back == "Back to the tour")
    }
}
