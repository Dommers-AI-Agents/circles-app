import Foundation
import Testing
@testable import Circles_iOS

/// The client half of the daily card's "within reason": the hourly fetch
/// throttle and the never-over-onboarding rules, plus card decoding and
/// target routing.
struct HomePromptGateTests {
    private func clear(now: Date = Date(), lastFetchAt: Date? = nil) -> HomePromptGate.Context {
        HomePromptGate.Context(
            now: now, lastFetchAt: lastFetchAt, isSignedIn: true, isCardVisible: false,
            isPresentingModal: false, isTourRunning: false, isFirstSessionFlowActive: false,
            onboardingCheckDone: true
        )
    }

    @Test func fetchesWhenTheScreenIsClearAndNoRecentFetch() {
        #expect(HomePromptGate.shouldFetch(clear()))
        #expect(HomePromptGate.shouldFetch(clear(now: Date(), lastFetchAt: Date().addingTimeInterval(-3601))))
    }

    @Test func throttlesToOnceAnHour() {
        let now = Date()
        #expect(!HomePromptGate.shouldFetch(clear(now: now, lastFetchAt: now.addingTimeInterval(-60))))
        #expect(!HomePromptGate.shouldFetch(clear(now: now, lastFetchAt: now.addingTimeInterval(-3599))))
    }

    @Test func neverOverOnboardingToursModalsOrAnExistingCard() {
        var c = clear(); c.isFirstSessionFlowActive = true
        #expect(!HomePromptGate.shouldFetch(c))
        c = clear(); c.isTourRunning = true
        #expect(!HomePromptGate.shouldFetch(c))
        c = clear(); c.isPresentingModal = true
        #expect(!HomePromptGate.shouldFetch(c))
        c = clear(); c.isCardVisible = true
        #expect(!HomePromptGate.shouldFetch(c))
        c = clear(); c.onboardingCheckDone = false
        #expect(!HomePromptGate.shouldFetch(c))
        c = clear(); c.isSignedIn = false
        #expect(!HomePromptGate.shouldFetch(c))
    }

    @Test func presentationRechecksTheScreenWhenTheResponseLands() {
        #expect(HomePromptGate.canPresent(clear()))
        var c = clear(); c.isPresentingModal = true
        #expect(!HomePromptGate.canPresent(c))
        c = clear(); c.isTourRunning = true
        #expect(!HomePromptGate.canPresent(c))
    }

    @Test func decodesAServerCardWithDefaultsAndMixedData() throws {
        let json = """
        {"success":true,"card":{"key":"activity:a1","type":"connection_activity","title":"Ana added Mabel's",
          "target":"place","data":{"placeId":"p1","globalPlaceId":null,"coins":12.5},"imageUrl":"https://x/p.jpg"}}
        """
        struct Envelope: Decodable { let card: HomePromptCard? }
        let card = try #require(JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).card)
        #expect(card.actionLabel == "Show me")
        #expect(card.skipLabel == "Skip")
        #expect(card.body == "")
        #expect(card.data["placeId"] == .string("p1"))
        #expect(card.data["globalPlaceId"] == .null)
        #expect(card.data["coins"] == .number(12.5))
        #expect(card.destination == .place(id: "p1"))
    }

    @Test func nullCardIsNothingToday() throws {
        struct Envelope: Decodable { let success: Bool; let card: HomePromptCard? }
        let env = try JSONDecoder().decode(Envelope.self, from: Data(#"{"success":true,"card":null}"#.utf8))
        #expect(env.card == nil)
    }

    @Test func targetsRouteAndUnknownOnesStayRenderable() {
        #expect(HomePromptTarget(target: "video", data: ["videoId": .string("v1")]) == .video(id: "v1"))
        #expect(HomePromptTarget(target: "moment", data: ["momentId": .string("v2")]) == .video(id: "v2"))
        #expect(HomePromptTarget(target: "video", data: [:]) == .unknown("video"))
        #expect(HomePromptTarget(target: "place", data: ["placeId": .string("")]) == .unknown("place"))
        #expect(HomePromptTarget(target: "add_place", data: [:]) == .addPlace)
        #expect(HomePromptTarget(target: "favcoins_intro", data: [:]) == .favCoinsIntro)
        #expect(HomePromptTarget(target: "widgets_tab", data: [:]) == .widgetsTab)
        #expect(HomePromptTarget(target: "moments_tab", data: [:]) == .momentsTab)
        #expect(HomePromptTarget(target: "all_places_map", data: [:]) == .allPlacesMap)
        #expect(HomePromptTarget(target: "create_wallet", data: [:]) == .createWallet)
        #expect(HomePromptTarget(target: "something_new", data: [:]) == .unknown("something_new"))
    }
}
