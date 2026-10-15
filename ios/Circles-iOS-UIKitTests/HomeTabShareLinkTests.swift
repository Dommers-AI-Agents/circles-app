import Testing
import Foundation
@testable import Circles_iOS

/// Sharing a home tab (Local / Widgets): the link the header's Share button
/// hands out, and the routes that bring the recipient to that tab — the
/// https shape a share sheet sends, the `circles://` shape the landing page
/// fires, and the cold-start stash.
@Suite("Home tab share links")
struct HomeTabShareLinkTests {
    private let router = DeepLinkRouter()

    @Test func onlyLocalAndWidgetsAreShareable() {
        #expect(HomeContentSegment.allCases.filter(\.showsShareButton) == [.specials, .widgets])
        #expect(HomeContentSegment.specials.shareSlug == "local")   // public name, not the case name
        #expect(HomeContentSegment.widgets.shareSlug == "widgets")
        #expect(HomeTabShareLink.url(for: .activity) == nil)
        #expect(HomeTabShareLink.url(for: .moments) == nil)
    }

    @Test func slugRoundTrips() {
        #expect(HomeContentSegment(shareSlug: "local") == .specials)
        #expect(HomeContentSegment(shareSlug: "Widgets") == .widgets)
        #expect(HomeContentSegment(shareSlug: "specials") == nil)
        #expect(HomeContentSegment(shareSlug: "moments") == nil)
    }

    @Test func builtLinkIsTheOneTheRouterUnderstands() {
        let local = HomeTabShareLink.url(for: .specials)
        #expect(local?.absoluteString == "https://api.favcircles.com/app/tab/local")
        #expect(local.flatMap(router.destination(for:)) == .homeTab(.specials))
        let widgets = HomeTabShareLink.url(for: .widgets)
        #expect(widgets?.absoluteString == "https://api.favcircles.com/app/tab/widgets")
        #expect(widgets.flatMap(router.destination(for:)) == .homeTab(.widgets))
        #expect(HomeTabShareLink.title(for: .specials) == "Local on FavCircles")
    }

    @Test func customSchemeFormsBothRoute() {
        #expect(router.destination(for: URL(string: "circles://tab/local")!) == .homeTab(.specials))
        #expect(router.destination(for: URL(string: "circles:///tab/widgets")!) == .homeTab(.widgets))
    }

    @Test func unknownOrMissingTabRoutesNowhere() {
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/tab/moments")!) == nil)
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/app/tab")!) == nil)
        #expect(router.destination(for: URL(string: "circles://tab")!) == nil)
    }

    @Test func coldStartStashParses() {
        #expect(PendingLinkParser.parse("tab:local") == .homeTab(.specials))
        #expect(PendingLinkParser.parse("tab:widgets") == .homeTab(.widgets))
        #expect(PendingLinkParser.parse("tab:nope") == nil)
    }

    @Test func cardDrawsForEveryShareableTab() {
        for segment in HomeContentSegment.allCases where segment.showsShareButton {
            let image = HomeTabShareCard.image(for: segment)
            #expect(image.size == HomeTabShareCard.size)
        }
    }
}
