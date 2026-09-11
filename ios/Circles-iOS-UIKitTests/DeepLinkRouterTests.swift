import Testing
import Foundation
@testable import Circles_iOS

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
