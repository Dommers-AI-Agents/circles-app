import Testing
@testable import Circles_iOS

/// The home tour: four basics, then "Keep going" for the rest (2026-11-01)
struct TutorialStepTests {
    @Test func basicsComeFirstAndCountSeparately() {
        #expect(Array(TutorialStep.allCases.prefix(4)) == TutorialStep.basics)
        #expect(TutorialStep.addPlaces.progressText == "1 of 4")
        #expect(TutorialStep.seeWidgets.progressText == "4 of 4")
        #expect(TutorialStep.moments.progressText == "1 of 10")
        #expect(TutorialStep.profile.progressText == "10 of 10")
        #expect(!TutorialStep.checkIn.isBasic)
    }

    /// Every button along the top and the bottom has a bubble (Wes, 2026-11-12)
    @Test func theTopAndBottomButtonsEachGetABubble() {
        let extras = TutorialStep.allCases.filter { !$0.isBasic }
        #expect(extras.contains(.checkIn) && extras.contains(.rewards) && extras.contains(.notifications)
                && extras.contains(.invite) && extras.contains(.help))
        #expect(extras.contains(.myNetwork) && extras.contains(.messages) && extras.contains(.profile))
        #expect(extras.last == .profile)
    }

    @Test func everyStepSaysSomething() {
        for step in TutorialStep.allCases {
            #expect(!step.title.isEmpty && !step.description.isEmpty)
        }
    }
}
