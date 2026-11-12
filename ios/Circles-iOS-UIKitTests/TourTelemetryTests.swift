import Testing
@testable import Circles_iOS

/// The home tour reports each bubble and button (2026-11-12)
struct TourTelemetryTests {
    @Test func anEventCarriesTheStepSurfaceAndAction() {
        #expect(TourTelemetry.event(step: TutorialStep.addPlaces.rawValue, action: .shown)
                == ["step": "tour_add_places", "surface": "home_tour", "kind": "shown"])
        #expect(TourTelemetry.event(step: TourTelemetry.keepGoingStep, action: .keepGoing)["kind"] == "keep_going")
        #expect(TourTelemetry.event(step: "tour_moments", action: .learnMore)["kind"] == "learn_more")
    }

    @Test func everyTourStepIdIsOneTheServerAccepts() {
        let serverSteps: Set<String> = ["tour_add_places", "tour_follow_users", "tour_view_activity", "tour_see_widgets",
                                        "tour_moments", "tour_locals", "tour_check_in", "tour_rewards", "tour_profile", "tour_keep_going"]
        for step in TutorialStep.allCases { #expect(serverSteps.contains(step.rawValue), "\(step)") }
        #expect(serverSteps.contains(TourTelemetry.keepGoingStep))
    }
}
