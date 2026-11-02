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

    @Test func theServersOrderDecidesAndSkippedStepsGoLast() {
        let mine: [NextStep] = [.postMoment, .myCheckIns]
        // A reward ready (server boost) leads the moment's own steps
        #expect(NextStep.rank(mine + [.myRewards], order: ["my_rewards", "post_moment", "my_check_ins"]) == [.myRewards, .postMoment])
        // No ranking yet: the moment's own order
        #expect(NextStep.rank(mine, order: []) == mine)
        // A step they keep skipping goes last
        #expect(NextStep.rank(mine, order: ["post_moment", "my_check_ins"], avoid: ["post_moment"]) == [.myCheckIns, .postMoment])
        // Never more than two, never twice
        #expect(NextStep.rank([.addPlace, .addPlace, .findPeople, .explore], order: []) == [.addPlace, .findPeople])
    }
}
