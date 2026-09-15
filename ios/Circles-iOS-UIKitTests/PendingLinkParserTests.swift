import Testing
@testable import Circles_iOS

/// Stored "pendingDeepLink" strings → navigation, as SceneDelegate parses them.
struct PendingLinkParserTests {
    @Test func singleTokenLinks() {
        #expect(PendingLinkParser.parse("network") == .network)
        #expect(PendingLinkParser.parse("daily-summary") == .dailySummary)
        #expect(PendingLinkParser.parse("all-places-map") == .allPlacesMap)
        #expect(PendingLinkParser.parse("create-wallet") == .createWallet)
        #expect(PendingLinkParser.parse("add-place") == .openPath("add-place"))
        #expect(PendingLinkParser.parse("me") == .openPath("me"))
    }

    @Test func typedLinks() {
        #expect(PendingLinkParser.parse("circle:c1") == .circle(id: "c1"))
        #expect(PendingLinkParser.parse("place:p1") == .place(id: "p1"))
        #expect(PendingLinkParser.parse("user:u1") == .user(id: "u1"))
        #expect(PendingLinkParser.parse("share:s1") == .share(id: "s1"))
        #expect(PendingLinkParser.parse("connect:u2") == .connect(fromUserId: "u2"))
        #expect(PendingLinkParser.parse("video:v1") == .video(id: "v1"))
        #expect(PendingLinkParser.parse("shareToken:c1:tok") == .shareToken(circleId: "c1", shareToken: "tok"))
        #expect(PendingLinkParser.parse("settings:notifications") == .notificationSettings)
        #expect(PendingLinkParser.parse("check-in:abc123") == .checkIn(placeId: "abc123"))
        #expect(PendingLinkParser.parse("daily-summary:anything") == .dailySummary)
    }

    @Test func malformedLinksNavigateNowhere() {
        #expect(PendingLinkParser.parse("") == nil)
        #expect(PendingLinkParser.parse("circle") == nil)
        #expect(PendingLinkParser.parse("circle:") == nil)          // empty segment dropped → one part
        #expect(PendingLinkParser.parse("shareToken:c1") == nil)    // needs the token
        #expect(PendingLinkParser.parse("settings:privacy") == nil)
        #expect(PendingLinkParser.parse("unknown:x") == nil)
        #expect(PendingLinkParser.parse("bogus") == nil)
    }

    @Test func extraSegmentsAreIgnoredAfterTheOnesUsed() {
        #expect(PendingLinkParser.parse("circle:c1:extra") == .circle(id: "c1"))
        #expect(PendingLinkParser.parse("shareToken:c1:tok:more") == .shareToken(circleId: "c1", shareToken: "tok"))
    }
}
