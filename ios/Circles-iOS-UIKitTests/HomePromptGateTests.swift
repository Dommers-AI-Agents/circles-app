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

    private func back(after away: TimeInterval?, now: Date = Date(), lastFetchAt: Date? = nil) -> HomePromptGate.Context {
        var c = clear(now: now, lastFetchAt: lastFetchAt)
        c.trigger = .foreground(sinceBackground: away)
        return c
    }

    @Test func theFirstAppearanceOfASessionFetches() {
        #expect(HomePromptGate.shouldFetch(clear()))
    }

    /// Switching back to the Home tab mid-session is not an arrival. Once
    /// anything has been fetched this session, appearing again never asks —
    /// otherwise the card would pop every time someone came back from a place.
    @Test func laterAppearancesNeverFetch() {
        let now = Date()
        #expect(!HomePromptGate.shouldFetch(clear(now: now, lastFetchAt: now.addingTimeInterval(-3601))))
        #expect(!HomePromptGate.shouldFetch(clear(now: now, lastFetchAt: now.addingTimeInterval(-86_400))))
    }

    /// A foreground counts as coming back only after a couple of hours away.
    @Test func foregroundFetchesOnlyAfterTwoHoursAway() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3 * 3600)
        #expect(!HomePromptGate.shouldFetch(back(after: 60, now: now, lastFetchAt: earlier)))
        #expect(!HomePromptGate.shouldFetch(back(after: 2 * 3600 - 1, now: now, lastFetchAt: earlier)))
        #expect(HomePromptGate.shouldFetch(back(after: 2 * 3600, now: now, lastFetchAt: earlier)))
        // If the app can't say how long it was gone, it errs toward asking —
        // the server's own window still decides whether anything shows.
        #expect(HomePromptGate.shouldFetch(back(after: nil, now: now, lastFetchAt: earlier)))
    }

    @Test func throttlesToOnceAnHourEvenWhenComingBack() {
        let now = Date()
        #expect(!HomePromptGate.shouldFetch(back(after: 3 * 3600, now: now, lastFetchAt: now.addingTimeInterval(-60))))
        #expect(!HomePromptGate.shouldFetch(back(after: 3 * 3600, now: now, lastFetchAt: now.addingTimeInterval(-3599))))
        #expect(HomePromptGate.shouldFetch(back(after: 3 * 3600, now: now, lastFetchAt: now.addingTimeInterval(-3601))))
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
        #expect(HomePromptTarget(target: "widget", data: ["widgetId": .string("heartbeat")]) == .widget(id: "heartbeat"))
        #expect(HomePromptTarget(target: "widget", data: [:]) == .unknown("widget"))
        #expect(HomePromptTarget(target: "inner_circle", data: [:]) == .innerCircle)
        #expect(HomePromptTarget(target: "something_new", data: [:]) == .unknown("something_new"))
    }

    @Test func scheduledCardsOverlay_organicCardsDoNot() {
        let json = """
        {"success":true,"card":{"key":"card:widget-launch","type":"custom","title":"Today's new widget",
          "body":"Water, habits, workouts.","actionLabel":"Show me","skipLabel":"Skip",
          "target":"widgets_tab","data":{},"presentation":"overlay"}}
        """
        struct Envelope: Decodable { let card: HomePromptCard? }
        let card = try! JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).card!
        #expect(card.isOverlay)
        #expect(card.destination == .widgetsTab)
        #expect(card.actionLabel == "Show me")

        // The server now asks for the overlay on every card it picks. The
        // model's own fallback is still inline: a card with NO presentation,
        // or an unrecognised one, must not take over the screen by accident.
        #expect(!HomePromptCard(key: "add_place", type: "add_place", title: "t", body: "b", target: "add_place").isOverlay)
        #expect(!HomePromptCard(key: "x", type: "custom", title: "t", body: "b", target: "network", presentation: "fullscreen").isOverlay)
    }

    @Test func postcardTargetNeedsBothAPlaceAndAPhoto() {
        let full = HomePromptTarget(target: "postcard", data: [
            "placeId": .string("p1"), "globalPlaceId": .string("g1"),
            "placeName": .string("Cafe Lisboa"), "photoUrl": .string("https://x/1.jpg")
        ])
        #expect(full == .postcard(placeId: "p1", globalPlaceId: "g1", placeName: "Cafe Lisboa", photoUrl: "https://x/1.jpg"))

        // A save with no canonical venue yet still routes — it just sends the
        // card without a globalPlaceId.
        #expect(HomePromptTarget(target: "postcard", data: [
            "placeId": .string("p1"), "globalPlaceId": .null, "photoUrl": .string("https://x/1.jpg")
        ]) == .postcard(placeId: "p1", globalPlaceId: nil, placeName: nil, photoUrl: "https://x/1.jpg"))

        // No photo, no card: the composer has nothing to open on.
        #expect(HomePromptTarget(target: "postcard", data: ["placeId": .string("p1")]) == .unknown("postcard"))
        #expect(HomePromptTarget(target: "postcard", data: ["photoUrl": .string("https://x/1.jpg")]) == .unknown("postcard"))
    }
}
