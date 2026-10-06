import Testing
import Foundation
@testable import Circles_iOS
import FavWidgets

/// Every link shape the emails, QR stickers, widget, share extension and App
/// Clip produce, pinned to the screen it must open.
struct DeepLinkRouterTests {
    private let router = DeepLinkRouter()
    private func dest(_ s: String) -> DeepLinkDestination? { router.destination(for: URL(string: s)!) }

    // MARK: Universal links

    @Test func brandedAndLegacyHostsBothRoute() {
        #expect(dest("https://api.favcircles.com/daily-summary") == .dailySummary)
        #expect(dest("https://circles-backend-196924649787.us-central1.run.app/daily-summary") == .dailySummary)
        #expect(dest("https://example.com/daily-summary") == nil)
    }

    @Test func appPrefixedPaths() {
        #expect(dest("https://api.favcircles.com/app/daily-summary") == .dailySummary)
        #expect(dest("https://api.favcircles.com/app/video/v1") == .video(id: "v1", promptsLogin: false))
        #expect(dest("https://api.favcircles.com/app/circle/c1") == .circle(id: "c1", shareToken: nil))
        #expect(dest("https://api.favcircles.com/app/circle/c1?share=tok") == .circle(id: "c1", shareToken: "tok"))
        #expect(dest("https://api.favcircles.com/app/connect/u1?code=ABC") == .connectionInvite(userId: "u1", referralCode: "ABC"))
        #expect(dest("https://api.favcircles.com/app/import") == .importFlow)
        #expect(dest("https://api.favcircles.com/app/map") == .allPlacesMap(focusCategory: nil))
        #expect(dest("https://api.favcircles.com/app/map?focus=coffee") == .allPlacesMap(focusCategory: "coffee"))
        #expect(dest("https://api.favcircles.com/app/unknown") == nil)
        #expect(dest("https://api.favcircles.com/app/video") == nil)   // missing id
        // An event's lock-screen display opens that event; the bare widget link still opens the widget
        #expect(dest("https://api.favcircles.com/app/widget/events?event=e1") == .eventOpen(id: "e1"))
        #expect(dest("https://api.favcircles.com/app/widget/events") == .widget(id: "events"))
        #expect(dest("https://api.favcircles.com/app/widget/run") == .widget(id: "run"))
        // "Watch my run" links open Map My Run on that run
        #expect(dest("https://api.favcircles.com/app/run/tok123") == .runJoin(token: "tok123"))
    }

    @Test func emailOpenPaths() {
        // Weekly summary email: "See my FavCoins" lands on the Piggy Bank
        #expect(router.openPathDestination("create-wallet") == .piggyBank)
        #expect(router.openPathDestination("rewards/piggy-bank") == .piggyBank)
        #expect(router.openPathDestination("settings/notifications") == .notificationSettings)
        #expect(router.openPathDestination("check-in") == .checkIn)
        // A texted workout opens in the Workouts widget, by universal link or scheme
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/workout/abcdefghijklmnopqrstuv")!) == .workout(token: "abcdefghijklmnopqrstuv"))
        #expect(router.destination(for: URL(string: "circles://workout/abcdefghijklmnopqrstuv")!) == .workout(token: "abcdefghijklmnopqrstuv"))
        #expect(router.openPathDestination("nope") == nil)
    }

    @Test func appOpenPathTargets() {
        #expect(dest("https://api.favcircles.com/app/open?path=settings/notifications") == .notificationSettings)
        #expect(dest("https://api.favcircles.com/app/open?path=network") == .network)
        #expect(dest("https://api.favcircles.com/app/open?path=network/find-friends") == .network)
        #expect(dest("https://api.favcircles.com/app/open?path=add-place") == .addPlace)
        #expect(dest("https://api.favcircles.com/app/open?path=me") == .meTab)
        #expect(dest("https://api.favcircles.com/app/open?path=nowhere") == nil)
        #expect(dest("https://api.favcircles.com/app/open") == nil)
    }

    @Test func topLevelSharedLinks() {
        #expect(dest("https://api.favcircles.com/video/v1") == .video(id: "v1", promptsLogin: false))
        #expect(dest("https://api.favcircles.com/share/video/v2") == .video(id: "v2", promptsLogin: false))
        #expect(dest("https://api.favcircles.com/share/circle/x") == nil)
        #expect(dest("https://api.favcircles.com/circle/c1?share=tok") == .circle(id: "c1", shareToken: "tok"))
        #expect(dest("https://api.favcircles.com/place/p1") == .place(id: "p1", refUserId: nil))
        #expect(dest("https://api.favcircles.com/place/p1?ref=u9") == .place(id: "p1", refUserId: "u9"))
        #expect(dest("https://api.favcircles.com/user/u1") == .userProfile(id: "u1"))
        #expect(dest("https://api.favcircles.com/connect/u1") == .connectionInvite(userId: "u1", referralCode: nil))
        // The sharer's signed invite rides along as ?t= (one-tap connect)
        #expect(dest("https://api.favcircles.com/connect/u1?code=R1&t=abc_DEF-123") == .connectionInvite(userId: "u1", referralCode: "R1", inviteToken: "abc_DEF-123"))
        #expect(dest("circles://connect/u1?t=tok") == .connectionInvite(userId: "u1", referralCode: nil, inviteToken: "tok"))
        #expect(dest("https://api.favcircles.com/s/AB12CD") == .sticker(code: "AB12CD"))
        #expect(dest("https://api.favcircles.com/") == nil)
    }

    // MARK: circles:// scheme

    @Test func hostBasedSchemeForms() {
        #expect(dest("circles://connect/u1?code=ref1") == .connectionInvite(userId: "u1", referralCode: "ref1"))
        #expect(dest("circles://video/v1") == .video(id: "v1", promptsLogin: true))
        #expect(dest("circles://referral?code=ABC123") == .referral(code: "ABC123"))
        #expect(dest("circles://sticker?code=AB12CD") == .sticker(code: "AB12CD"))
        #expect(dest("circles://daily-summary") == .dailySummary)
        #expect(dest("circles://place/p1") == .placeFromExtension(id: "p1"))
        #expect(dest("circles://upgrade") == .upgradePaywall)
        #expect(dest("circles://network") == .network)
        #expect(dest("circles://settings/notifications") == .notificationSettings)
        #expect(dest("circles://settings/other") == nil)
        #expect(dest("circles://circle/c1") == .circle(id: "c1", shareToken: nil))
        #expect(dest("circles://circle/c1?share=tok") == .circle(id: "c1", shareToken: "tok"))
    }

    @Test func hostFormsWithoutAnIdFallThrough() {
        #expect(dest("circles://connect") == nil)
        #expect(dest("circles://video") == nil)
        #expect(dest("circles://place") == nil)
        #expect(dest("circles://referral") == nil)     // no code
        #expect(dest("circles://circle") == nil)
    }

    @Test func pathBasedSchemeForms() {
        #expect(dest("circles:///circle/c1") == .circle(id: "c1", shareToken: nil))
        #expect(dest("circles:///circle/c1?share=tok") == .circle(id: "c1", shareToken: "tok"))
        #expect(dest("circles:///share/circle/s1") == .sharedCircle(shareId: "s1"))
        #expect(dest("circles:///place/p1?ref=u2") == .place(id: "p1", refUserId: "u2"))
        #expect(dest("circles:///user/u1") == .userProfile(id: "u1"))
        #expect(dest("circles:///connect/u1") == .connectionInvite(userId: "u1", referralCode: nil))
        #expect(dest("circles:///nothing/here") == nil)
    }

    @Test func otherSchemesAreIgnored() {
        #expect(dest("myapp://place/p1") == nil)
        #expect(dest("http://api.favcircles.com/place/p1") == .place(id: "p1", refUserId: nil))
    }
}

/// Shared widget links. Both shapes matter: the https one is what a share
/// sheet hands out, the `circles://` one is what the landing page fires at a
/// device that turns out to have the app after all.
@Suite("Widget share links")
struct WidgetShareLinkTests {
    private let router = DeepLinkRouter()

    @Test func universalLinkOpensTheWidget() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/widget/sleepsounds")!)
                == .widget(id: "sleepsounds"))
        #expect(router.destination(for: URL(string: "https://circles-backend-196924649787.us-central1.run.app/app/widget/water")!)
                == .widget(id: "water"))
    }

    @Test func customSchemeFormsBothRoute() {
        #expect(router.destination(for: URL(string: "circles://widget/postcard")!) == .widget(id: "postcard"))
        #expect(router.destination(for: URL(string: "circles:///widget/postcard")!) == .widget(id: "postcard"))
    }

    @Test func widgetWithoutAnIdRoutesNowhere() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/widget")!) == nil)
        #expect(router.destination(for: URL(string: "circles://widget")!) == nil)
    }

    @Test func builtLinkIsTheOneTheRouterUnderstands() {
        let url = WidgetShareLink.url(widgetId: "heartbeat")
        #expect(url?.absoluteString == "https://api.favcircles.com/app/widget/heartbeat")
        #expect(url.flatMap(router.destination(for:)) == .widget(id: "heartbeat"))
    }

    @Test func aBrokenIdNeverBecomesALink() {
        #expect(WidgetShareLink.url(widgetId: "") == nil)
        #expect(WidgetShareLink.url(widgetId: "has space") == nil)
        #expect(WidgetShareLink.url(widgetId: "../../etc") == nil)
    }

    /// The pitch Wes asked for, word for word, from the widget's own share
    /// blurb — and nothing else: the link already names the widget.
    @Test @MainActor func heartbeatSharesAsTheCameraPitch() {
        let heartbeat = HeartbeatWidget().descriptor
        #expect(WidgetShareLink.message(title: heartbeat.title, subtitle: heartbeat.shareText)
                == "Measure your heart rate directly from your phone camera.")
    }

    @Test func messageIsOneSentenceAndSurvivesAnEmptySubtitle() {
        #expect(WidgetShareLink.message(title: "Water", subtitle: "Tap to log each glass") == "Tap to log each glass.")
        #expect(WidgetShareLink.message(title: "Water", subtitle: "Check on Mom or Dad?") == "Check on Mom or Dad?")
        #expect(WidgetShareLink.message(title: "Water", subtitle: "  ") == "Water on FavCircles")
    }
}

/// Shared quote links: the reel's Share button hands out the https form, the
/// landing page fires the `circles://` form at a phone that has the app.
@Suite("Quote share links")
struct QuoteShareLinkTests {
    private let router = DeepLinkRouter()

    @Test func universalLinkOpensTheQuote() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/quote/angelou-rainbow")!)
                == .quote(id: "angelou-rainbow"))
    }

    @Test func customSchemeFormsBothRoute() {
        #expect(router.destination(for: URL(string: "circles://quote/ashe-start")!) == .quote(id: "ashe-start"))
        #expect(router.destination(for: URL(string: "circles:///quote/ashe-start")!) == .quote(id: "ashe-start"))
    }

    @Test func quoteWithoutAnIdRoutesNowhere() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/quote")!) == nil)
        #expect(router.destination(for: URL(string: "circles://quote")!) == nil)
    }
}

/// Received postcards: the printed card's QR is the https form, the web
/// page's "Open it in the app" button is the `circles://` form.
@Suite("Postcard share links")
struct PostcardShareLinkTests {
    private let router = DeepLinkRouter()

    @Test func qrUniversalLinkOpensTheCard() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/postcard/abcdefghijklmnopqrst")!)
                == .postcardShare(token: "abcdefghijklmnopqrst"))
    }

    @Test func customSchemeFormsBothRoute() {
        #expect(router.destination(for: URL(string: "circles://postcard/abcdefghijklmnopqrst")!) == .postcardShare(token: "abcdefghijklmnopqrst"))
        #expect(router.destination(for: URL(string: "circles:///postcard/abcdefghijklmnopqrst")!) == .postcardShare(token: "abcdefghijklmnopqrst"))
    }

    @Test func withoutATokenRoutesNowhere() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/postcard")!) == nil)
        #expect(router.destination(for: URL(string: "circles://postcard")!) == nil)
    }
}

/// Event invites: the group-text link is the https form, the web page's
/// button is the `circles://` form.
@Suite("Event invite links")
struct EventInviteLinkTests {
    private let router = DeepLinkRouter()

    @Test func universalAndCustomSchemeLinksOpenTheJoinScreen() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/event/abcdefghijklmnopqrst")!) == .eventInvite(token: "abcdefghijklmnopqrst"))
        #expect(router.destination(for: URL(string: "circles://event/abcdefghijklmnopqrst")!) == .eventInvite(token: "abcdefghijklmnopqrst"))
        #expect(router.destination(for: URL(string: "circles:///event/abcdefghijklmnopqrst")!) == .eventInvite(token: "abcdefghijklmnopqrst"))
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/event")!) == nil)
    }
}
