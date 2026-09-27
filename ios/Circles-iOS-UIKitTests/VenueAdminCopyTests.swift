import Testing
import Foundation
@testable import Circles_iOS

/// The super-user store page's plain-language copy.
struct VenueAdminCopyTests {
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    private func loyalty(_ reason: String, active: Bool = true, until: String? = nil, why: String? = nil) -> AdminVenueLoyalty {
        AdminVenueLoyalty(active: active, reason: reason, comped: reason == "comp", compedUntil: until, compReason: why)
    }

    private func owner(superUser: Bool = false, verified: Bool = false, expires: String? = nil) -> AdminVenueAccount {
        AdminVenueAccount(
            userId: "u1", displayName: "Owner", email: "o@example.com", username: nil,
            subscriptionStatus: "active", subscriptionExpiresAt: expires, subscriptionVenueId: "v1",
            manuallyVerified: verified, isSuperUser: superUser
        )
    }

    private func line(_ l: AdminVenueLoyalty, _ o: AdminVenueAccount?) -> VenueAdminCopy.LoyaltyLine {
        VenueAdminCopy.loyalty(l, owner: o, locale: locale, timeZone: utc)
    }

    @Test func compWithEndDateAndReason() {
        let l = line(loyalty("comp", until: "2026-12-01T00:00:00.000Z", why: "storefront_demo"), nil)
        #expect(l.title == "Loyalty live · comped")
        #expect(l.detail.hasPrefix("Free until Dec 1, 2026. Reason: storefront demo."))
        #expect(l.tone == .good)
    }

    @Test func openEndedComp() {
        #expect(line(loyalty("comp"), nil).detail.hasPrefix("Free with no end date."))
    }

    @Test func adminOwnerIsNotCalledAPaidPlan() {
        let l = line(loyalty("owner_premium"), owner(superUser: true, expires: "2026-08-01T15:19:35.000Z"))
        #expect(l.title == "Loyalty live · admin owner")
        #expect(!l.detail.contains("Renews"))
    }

    @Test func manuallyVerifiedOwner() {
        #expect(line(loyalty("owner_premium"), owner(verified: true)).title == "Loyalty live · verified owner")
    }

    @Test func paidPlanShowsRenewal() {
        let l = line(loyalty("owner_premium"), owner(expires: "2026-10-12T00:00:00Z"))
        #expect(l.title == "Loyalty live · Business plan")
        #expect(l.detail.hasSuffix("Renews Oct 12, 2026."))
    }

    @Test func lapsedAndUnowned() {
        #expect(line(loyalty("lapsed", active: false), owner()).tone == .warning)
        #expect(line(loyalty("no_owner", active: false), nil).title == "No owner yet")
    }

    @Test func tilesCarryMonthNotesOnlyWhenNonZero() {
        let stats = AdminVenueDetailStats(
            scans: 10, signups: 2, stickerSaves: 3, savers: 7, followers: 1, visits: 4,
            redemptions: 0, codeRedemptions: 0, clipScans: 0, clipSignups: 0, clipInstalls: 0
        )
        let month = AdminVenueMonthStats(scans: 3, signups: 0, stickerSaves: 0, visits: 1, redemptions: 0)
        let tiles = VenueAdminCopy.statTiles(stats, thisMonth: month)
        #expect(tiles.first { $0.title == "Scans" }?.monthNote == "+3 this month")
        #expect(tiles.first { $0.title == "Signups" }?.monthNote == nil)
        #expect(!tiles.contains { $0.title == "Codes used" })
        #expect(VenueAdminCopy.appClipLine(stats) == nil)
    }

    @Test func appClipLinePluralizes() {
        let stats = AdminVenueDetailStats(
            scans: 0, signups: 0, stickerSaves: 0, savers: 0, followers: 0, visits: 0,
            redemptions: 0, codeRedemptions: 2, clipScans: 4, clipSignups: 1, clipInstalls: 0
        )
        #expect(VenueAdminCopy.appClipLine(stats) == "App Clip: 4 scans · 1 signup · 0 installs")
        #expect(VenueAdminCopy.statTiles(stats, thisMonth: AdminVenueMonthStats(scans: 0, signups: 0, stickerSaves: 0, visits: 0, redemptions: 0))
            .contains { $0.title == "Codes used" })
    }

    @Test func registerExplanationMentionsPause() {
        #expect(VenueAdminCopy.registerCardExplanation(earnRate: 25, loyaltyActive: true).contains("earns 25 points, once a day."))
        #expect(VenueAdminCopy.registerCardExplanation(earnRate: 1, loyaltyActive: false).hasSuffix("Paused until loyalty is live."))
    }

    @Test func addressDropsDistanceSuffix() {
        #expect(VenueAdminCopy.cleanAddress("332, W Bland St, Charlotte, NC\n📍 0 mi from current location") == "332, W Bland St, Charlotte, NC")
        #expect(VenueAdminCopy.cleanAddress("  ") == nil)
        #expect(VenueAdminCopy.cleanAddress(nil) == nil)
    }
}
