import Testing
@testable import Circles_iOS

/// The home tour: four basics, then "Keep going" for the rest (2026-11-01)
struct TutorialStepTests {
    @Test func basicsComeFirstAndCountSeparately() {
        #expect(Array(TutorialStep.allCases.prefix(4)) == TutorialStep.basics)
        #expect(TutorialStep.addPlaces.progressText == "1 of 4")
        #expect(TutorialStep.seeWidgets.progressText == "4 of 4")
        #expect(TutorialStep.moments.progressText == "1 of 5")
        #expect(TutorialStep.profile.progressText == "5 of 5")
        #expect(!TutorialStep.checkIn.isBasic)
    }

    @Test func everyStepSaysSomething() {
        for step in TutorialStep.allCases {
            #expect(!step.title.isEmpty && !step.description.isEmpty)
        }
    }
}
