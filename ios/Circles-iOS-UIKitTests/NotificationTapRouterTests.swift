import Testing
import Foundation
@testable import Circles_iOS

/// Every push type the server sends, pinned to where a tap lands. This is
/// the table the 270-line AppDelegate switch never had.
struct NotificationTapRouterTests {
    private func route(_ info: [AnyHashable: Any]) -> NotificationDestination? {
        NotificationTapRouter.destination(for: info)
    }

    @Test func typeIsFoundWhereverTheSenderPutIt() {
        #expect(NotificationTapRouter.type(in: ["type": "x"]) == "x")
        #expect(NotificationTapRouter.type(in: ["customData": ["type": "y"]]) == "y")
        #expect(NotificationTapRouter.type(in: ["data": ["type": "z"]]) == "z")
        #expect(NotificationTapRouter.type(in: ["placeId": "p"]) == nil)
        #expect(route(["placeId": "p"]) == nil)
    }

    @Test func messagesAndWidgets() {
        #expect(route(["type": "new_message", "conversationId": "c1"]) == .conversation(id: "c1"))
        #expect(route(["type": "new_message"]) == .messages)
        #expect(route(["type": "nextbar_round"]) == .homeWidget(id: "nextbar"))
        #expect(route(["type": "fridgemail"]) == .homeWidget(id: "fridgemail"))
        #expect(route(["type": "postcard_order"]) == .homeWidget(id: "postcard"))
        #expect(route(["type": "postcard_order", "orderId": "o1"]) == .postcardOrder(id: "o1"))
        #expect(route(["type": "postcard_order", "data": ["orderId": "o2"]]) == .postcardOrder(id: "o2"))
        #expect(route(["type": "postcard_order", "orderId": ""]) == .homeWidget(id: "postcard"))
        #expect(route(["type": "water_reminder"]) == .homeWidget(id: "water"))
        // One push type per question kind (the Lock Screen buttons differ); all open the widget.
        for t in ["care_invite", "care_ask", "care_ask_done", "care_ask_yesno", "care_ask_scale", "care_ask_text", "care_answer", "care_accepted", "care_silence",
                  "care_watcher_request", "care_watcher_invite", "care_watcher_accepted", "care_watcher_declined", "care_watcher_joined", "care_watcher_removed"] {
            #expect(route(["type": t]) == .homeWidget(id: "howareyou"))
        }
    }

    @Test func placesCirclesAndActivity() {
        #expect(route(["type": "new_suggestion", "placeId": "p", "suggestionId": "s"]) == .suggestions(placeId: "p", suggestionId: "s"))
        #expect(route(["type": "new_suggestion"]) == .suggestions(placeId: nil, suggestionId: nil))
        #expect(route(["type": "new_place", "circleId": "c"]) == .circle(id: "c", showComments: nil))
        #expect(route(["type": "new_place"]) == nil)
        #expect(route(["type": "place_commented", "placeId": "p"]) == .place(id: "p", showComments: true))
        #expect(route(["type": "place_liked", "placeId": "p"]) == .place(id: "p", showComments: false))
        #expect(route(["type": "place_liked", "activityId": "a"]) == .activity(id: "a"))
        #expect(route(["type": "circle_commented", "circleId": "c"]) == .circle(id: "c", showComments: true))
        #expect(route(["type": "circle_liked", "activityId": "a"]) == .activity(id: "a"))
        #expect(route(["type": "activity_like", "activityId": "a"]) == .activity(id: "a"))
        #expect(route(["type": "activity_update"]) == .activity(id: nil))
    }

    @Test func checkInsKeepTheArmThatActuallyRan() {
        // The old switch listed "check_in"/"checkin" twice; only the first arm
        // (place, else activity) was reachable. check_in_response never had
        // the activity fallback.
        #expect(route(["type": "check_in", "placeId": "p"]) == .place(id: "p", showComments: nil))
        #expect(route(["type": "checkin", "activityId": "a"]) == .activity(id: "a"))
        #expect(route(["type": "check_in_response", "placeId": "p"]) == .place(id: "p", showComments: nil))
        #expect(route(["type": "check_in_response", "activityId": "a"]) == nil)
    }

    @Test func networkSummaryAndStashedLinks() {
        #expect(route(["type": "connection_request"]) == .network(showPending: true))
        #expect(route(["type": "connection_accepted", "acceptedByUserId": "u"]) == .connectionAccepted(userId: "u"))
        #expect(route(["type": "connection_accepted"]) == .network(showPending: false))
        #expect(route(["type": "daily_summary"]) == .dailySummary)
        #expect(route(["type": "all_places_map"]) == .postOrStash(navName: "NavigateToAllPlacesMap", pending: "all-places-map", object: nil))
        #expect(route(["type": "create_wallet"]) == .postOrStash(navName: "NavigateToCreateWallet", pending: "create-wallet", object: nil))
        #expect(route(["type": ProximityNotificationScheduler.notificationType, "placeId": "p"]) == .proximityCheckIn(placeId: "p"))
        #expect(route(["type": ProximityNotificationScheduler.notificationType, "placeId": ""]) == nil)
        // The opt-out banner is the same notification with one more button.
        #expect(route(["type": ProximityNotificationScheduler.notificationType, "placeId": "p",
                       "category": ProximityNotificationScheduler.optOutCategoryIdentifier]) == .proximityCheckIn(placeId: "p"))
        #expect(route(["type": "favcoin_claim_settled"]) == .piggyBank)
    }

    @Test func peopleMomentsAndStores() {
        #expect(route(["type": "new_follower", "fromUserId": "u"]) == .userProfile(id: "u"))
        #expect(route(["type": "user_followed", "actorId": "u"]) == .userProfile(id: "u"))
        #expect(route(["type": "new_follower"]) == nil)
        #expect(route(["type": "moment_tag", "momentId": "m"]) == .video(id: "m"))
        #expect(route(["type": "video_liked", "placeId": "p"]) == .place(id: "p", showComments: nil))
        #expect(route(["type": "store_claim"]) == .meTab)
    }

    @Test func unknownTypesRouteOnTheDataTheyCarryInTheOldOrder() {
        #expect(route(["type": "mystery", "activityId": "a", "placeId": "p"]) == .activity(id: "a"))
        #expect(route(["type": "mystery", "circleId": "c", "placeId": "p"]) == .circle(id: "c", showComments: nil))
        #expect(route(["type": "mystery", "placeId": "p", "conversationId": "c"]) == .place(id: "p", showComments: nil))
        #expect(route(["type": "mystery", "conversationId": "c"]) == .conversation(id: "c"))
        #expect(route(["type": "mystery", "videoId": "v"]) == .video(id: "v"))
        #expect(route(["type": "mystery", "actorId": "u"]) == .userProfile(id: "u"))
        #expect(route(["type": "mystery", "deepLink": "circles://place/1"]) == .deepLink(URL(string: "circles://place/1")!))
        #expect(route(["type": "mystery", "deepLink": "https://x"]) == nil)
        #expect(route(["type": "mystery"]) == nil)
    }
}

/// The quote of the day. The push has carried `quoteId` since it shipped and
/// nothing on the client read it — a tap went nowhere.
@Suite("Daily quote taps")
struct DailyQuoteTapTests {
    @Test func aQuoteTapOpensThatQuote() {
        #expect(NotificationTapRouter.destination(for: ["type": "daily_quote", "quoteId": "rumi-wound"])
                == .dailyQuote(id: "rumi-wound"))
    }

    @Test func nestedPayloadsAreReadTheSameWay() {
        #expect(NotificationTapRouter.destination(for: ["data": ["type": "daily_quote", "quoteId": "ashe-start"]])
                == .dailyQuote(id: "ashe-start"))
    }

    @Test func withoutAnIdItStillOpensTheWidget() {
        // An older server, or a quote retired since — the page is better than
        // nowhere, which is where these taps used to go.
        #expect(NotificationTapRouter.destination(for: ["type": "daily_quote"]) == .homeWidget(id: "quotes"))
    }

    @Test func theColdStartShapeRoundTrips() {
        // A push tap is the cold-start case: killed app, no tab bar yet, so
        // the id rides through UserDefaults as "quote:<id>".
        #expect(PendingLinkParser.parse("quote:rumi-wound") == .quote(id: "rumi-wound"))
    }
}
