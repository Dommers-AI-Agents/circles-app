import Testing
@testable import Circles_iOS

/// Never a dead end (2026-11-02): every moment offers one or two next taps
struct NextStepTests {
    @Test func everyMomentOffersOneOrTwoSteps() {
        let moments: [NextStep.Moment] = [.checkedIn, .checkedInAtRewardsStore, .momentPosted, .followed,
                                          .storeOffersSaved, .storeDetailsSaved, .circleSaved, .suggestionSent, .connectionAccepted]
        for moment in moments {
            let steps = NextStep.after(moment)
            #expect((1...2).contains(steps.count), "\(moment)")
            #expect(Set(steps.map(\.id)).count == steps.count)
        }
    }

    @Test func aRewardsStoreCheckInLeadsWithPoints() {
        #expect(NextStep.after(.checkedInAtRewardsStore).first == .scanForPoints)
    }
}
