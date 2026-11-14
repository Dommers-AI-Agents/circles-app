import Testing
import Foundation
@testable import Circles_iOS

/// Coupons (2026-11-14): the owner's draft check, the scan's words, the
/// customer's rows, and the server shapes decoding leniently.
struct StoreCouponTests {

    private let far = "2026-12-05T04:59:00.000Z"

    private func claim(status: String, onlineCode: String? = "TGOSTVQC", usedAt: String? = nil) -> StoreCoupon {
        StoreCoupon(claimId: "v1_u1_ABCDEF", venueId: "v1", venueName: "Vero", couponId: "ABCDEF", title: "20% off any pickup order",
                    detail: "Max $20", onlineCode: onlineCode, campaign: "Nov mailer", expiresAt: far, claimedAt: "2026-11-14T18:00:00.000Z",
                    status: status, voucherId: status == "ticket" ? "t1" : nil, usedAt: usedAt)
    }

    @Test func theDraftRefusesWhatTheServerWould() {
        var draft = VenueCouponEdit(expiresAt: Date().addingTimeInterval(86400))
        #expect(draft.problem()?.contains("Say what the coupon gives") == true)
        draft.title = " 20% off any pickup order "
        #expect(draft.problem() == nil)
        draft.onlineCode = "no spaces!"
        #expect(draft.problem()?.contains("letters and numbers") == true)
        draft.onlineCode = "tgostvqc"
        draft.maxClaimsText = "zero"
        #expect(draft.problem()?.contains("whole number") == true)
        draft.maxClaimsText = "500"
        draft.expiresAt = Date().addingTimeInterval(-60)
        #expect(draft.problem()?.contains("hasn") == true)
        draft.expiresAt = Date().addingTimeInterval(86400)
        #expect(draft.problem() == nil)
        let body = draft.asBody
        #expect(body["title"] as? String == "20% off any pickup order")
        #expect(body["onlineCode"] as? String == "TGOSTVQC")
        #expect(body["maxClaims"] as? Int == 500)
        #expect((body["expiresAt"] as? String)?.hasSuffix("Z") == true)
        draft.maxClaimsText = ""
        #expect(draft.asBody["maxClaims"] is NSNull)
    }

    @Test func theScanSaysWhatHappenedToTheCoupon() {
        let offer = StoreCouponOffer(couponId: "ABCDEF", title: "20% off any pickup order", detail: nil, onlineCode: "TGOSTVQC", expiresAt: far)
        let claimed = ScanCouponResult(status: "claimed", coupon: offer, claim: claim(status: "claimed"), voucher: nil)
        let line = StoreCouponCopy.scanLine(claimed, storeName: "Vero")!
        #expect(line.hasPrefix("Your coupon is saved: 20% off any pickup order."))
        #expect(line.contains("through Dec"))
        #expect(line.contains("Use code TGOSTVQC"))
        #expect(StoreCouponCopy.scanLine(ScanCouponResult(status: "already", coupon: offer, claim: claim(status: "used"), voucher: nil), storeName: "Vero") == "You've already used this coupon (20% off any pickup order).")
        #expect(StoreCouponCopy.scanLine(ScanCouponResult(status: "already", coupon: offer, claim: claim(status: "claimed"), voucher: nil), storeName: "Vero")?.hasPrefix("You already have this coupon") == true)
        #expect(StoreCouponCopy.scanLine(ScanCouponResult(status: "full", coupon: offer, claim: nil, voucher: nil), storeName: "Vero") == "That coupon (20% off any pickup order) has all been claimed.")
        #expect(StoreCouponCopy.scanLine(ScanCouponResult(status: "paused", coupon: offer, claim: nil, voucher: nil), storeName: "Vero") == "Vero has paused that coupon (20% off any pickup order).")
        #expect(StoreCouponCopy.scanLine(ScanCouponResult(status: "not_found", coupon: nil, claim: nil, voucher: nil), storeName: "Vero") == nil)
        let ticket = ScanCouponResult(status: "ticket", coupon: nil, claim: claim(status: "ticket"), voucher: nil)
        #expect(StoreCouponCopy.ticketLine(ticket) == "Your coupon is open: 20% off any pickup order. Show the ticket at the counter.")
        #expect(StoreCouponCopy.ticketButton(ticket) == "Show my coupon")
        #expect(StoreCouponCopy.ticketButton(claimed) == nil)
    }

    @Test func theCustomersRowsAndButtons() {
        #expect(StoreCouponCopy.claimDetail(claim(status: "claimed")).hasPrefix("Max $20 · Ends Dec"))
        #expect(StoreCouponCopy.claimDetail(claim(status: "claimed")).hasSuffix("· Online code TGOSTVQC"))
        #expect(StoreCouponCopy.claimDetail(claim(status: "ticket")) == "Max $20 · Ticket open · show it at the counter · Online code TGOSTVQC")
        #expect(StoreCouponCopy.claimDetail(claim(status: "used", onlineCode: nil, usedAt: "2026-11-20T18:00:00.000Z")).hasPrefix("Max $20 · Used Nov 20"))
        #expect(StoreCouponCopy.useButton(claim(status: "claimed")) == "Use now")
        #expect(StoreCouponCopy.useButton(claim(status: "ticket")) == "Show ticket")
        #expect(StoreCouponCopy.useButton(claim(status: "used")) == nil)
        #expect(claim(status: "ticket").isOpen && !claim(status: "used").isOpen)
    }

    @Test func theOwnersList() {
        let counts = VenueCouponCounts(scans: 84, claims: 31, tickets: 14, redemptions: 12, newCustomers: 9)
        let live = VenueCoupon(couponId: "ABCDEF", title: "20% off", detail: nil, onlineCode: nil, campaign: "Nov mailer", expiresAt: far,
                               maxClaims: 500, active: true, createdAt: nil, url: "https://api.favcircles.com/s/WIN?c=ABCDEF", counts: counts, state: "live")
        #expect(StoreCouponCopy.ownerLine(live).hasPrefix("Ends Dec"))
        #expect(StoreCouponCopy.ownerLine(live).hasSuffix("Nov mailer · 84 scans · 31 claimed · 12 used"))
        let paused = VenueCoupon(couponId: "X", title: "x", detail: nil, onlineCode: nil, campaign: nil, expiresAt: far, maxClaims: nil, active: false,
                                 createdAt: nil, url: nil, counts: nil, state: "paused")
        #expect(StoreCouponCopy.ownerLine(paused) == "Paused")
        #expect(StoreCouponCopy.summary([live, paused]) == "1 live · 31 claimed · 12 used")
        #expect(StoreCouponCopy.summary([]) == StoreCouponCopy.rowSubtitle)
        #expect(StoreCouponCopy.tiles(live).map(\.value) == ["84", "31 / 500", "12", "9"])
        #expect(StoreCouponCopy.shareTitle(storeName: "Vero", coupon: live) == "20% off at Vero — scan to claim it")
    }

    @Test func aScanWithACouponDecodesAndAScanWithoutOneStillDoes() throws {
        let json = """
        {"kind":"window","venue":{"venueId":"v1","venueName":"Vero"},"awarded":null,"saved":true,"alreadySaved":false,"savedPlace":null,"balance":0,"venueBalance":0,"loyaltyLive":true,"offers":[],
         "coupon":{"status":"claimed","coupon":{"couponId":"ABCDEF","title":"20% off","detail":null,"onlineCode":"TGOSTVQC","expiresAt":"\(far)"},
                   "claim":{"claimId":"v1_u1_ABCDEF","venueId":"v1","venueName":"Vero","couponId":"ABCDEF","title":"20% off","detail":null,"onlineCode":"TGOSTVQC","campaign":null,"expiresAt":"\(far)","claimedAt":"2026-11-14T18:00:00.000Z","status":"claimed","voucherId":null,"usedAt":null}}}
        """
        let scan = try JSONDecoder().decode(RewardScanData.self, from: Data(json.utf8))
        #expect(scan.coupon?.status == "claimed")
        #expect(scan.coupon?.claim?.claimId == "v1_u1_ABCDEF")
        let plain = try JSONDecoder().decode(RewardScanData.self, from: Data("""
        {"kind":"window","venue":{"venueId":"v1","venueName":"Vero"},"awarded":null,"saved":true,"alreadySaved":false,"savedPlace":null,"balance":0,"offers":[]}
        """.utf8))
        #expect(plain.coupon == nil)
        // A shape this build doesn't know never sinks the scan
        let odd = try JSONDecoder().decode(RewardScanData.self, from: Data("""
        {"kind":"window","venue":{"venueId":"v1","venueName":"Vero"},"awarded":null,"saved":true,"alreadySaved":false,"savedPlace":null,"balance":0,"offers":[],"coupon":{"status":7}}
        """.utf8))
        #expect(odd.coupon == nil)
        // The register scan's ticket is a 0-point voucher with the online code
        let ticket = try JSONDecoder().decode(RewardVoucher.self, from: Data("""
        {"voucherCode":"C001","offerTitle":"20% off","pointsCost":0,"venueName":"Vero","expiresAt":"\(far)","voucherId":"t1","venueId":"v1","status":"issued","couponId":"ABCDEF","onlineCode":"TGOSTVQC"}
        """.utf8))
        #expect(ticket.isCoupon && ticket.onlineCode == "TGOSTVQC")
    }
}
