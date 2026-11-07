import Foundation
import Testing
@testable import Circles_iOS

struct ReceiptReaderTests {
    private static let now: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 6; c.hour = 18
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    private func day(_ date: Date?) -> String? {
        ReceiptReading(text: "", storeNameFound: false, orderDate: date).orderDay
    }

    @Test func doorDash() {
        let lines = ["DoorDash", "Order Details", "Ilios Crafted Greek - SouthEnd", "Order #A1B2-C3D4",
                     "Delivered Nov 5, 2026 at 7:42 PM", "Subtotal $21.00", "Total $27.85"]
        let r = ReceiptReader.read(lines: lines, venueName: "Ilios Crafted Greek", now: Self.now)
        #expect(r.deliveryApp == "DoorDash")
        #expect(r.storeNameFound)
        #expect(r.storeLine == "Ilios Crafted Greek - SouthEnd")
        #expect(r.orderNumber == "A1B2-C3D4")
        #expect(day(r.orderDate) == "2026-11-05")
        #expect(r.total == "$27.85")
    }

    @Test func uberEats() {
        let lines = ["Uber Eats", "Thanks for ordering, Wes", "Here's your receipt for Sal's Pizza Kitchen.",
                     "11/04/26", "Order ID: 3F2A1", "Total $18.10"]
        let r = ReceiptReader.read(lines: lines, venueName: "Sal's Pizza Kitchen", now: Self.now)
        #expect(r.deliveryApp == "Uber Eats")
        #expect(r.storeNameFound)
        #expect(r.orderNumber == "3F2A1")
        #expect(day(r.orderDate) == "2026-11-04")
    }

    @Test func grubhub() {
        let lines = ["GRUBHUB", "Fresh Monkee", "Order number 123456789", "Thursday, November 5", "Total: $12.40"]
        let r = ReceiptReader.read(lines: lines, venueName: "Fresh Monkee", now: Self.now)
        #expect(r.deliveryApp == "Grubhub")
        #expect(r.orderNumber == "123456789")
        #expect(day(r.orderDate) == "2026-11-05")
        #expect(r.total == "$12.40")
    }

    @Test func anotherStoresReceiptDoesntNameThisOne() {
        let r = ReceiptReader.read(lines: ["DoorDash", "Zeus Greek Kitchen", "Order #ZZ99"], venueName: "Ilios Crafted Greek", now: Self.now)
        #expect(!r.storeNameFound)
    }

    @Test func aTimeAloneIsntADate() {
        #expect(ReceiptReader.orderDate(in: "Delivered at 7:42 PM", now: Self.now) == nil)
    }

    @Test func orderDetailsIsntANumber() {
        #expect(ReceiptReader.orderNumber(in: ["Order Details", "Order total"]) == nil)
    }

    @Test func aWeekAndAHalfIsTooOld() {
        #expect(ReceiptReader.isTooOld(Self.now.addingTimeInterval(-10 * 86_400), now: Self.now))
        #expect(!ReceiptReader.isTooOld(Self.now.addingTimeInterval(-2 * 86_400), now: Self.now))
        #expect(!ReceiptReader.isTooOld(nil, now: Self.now))
    }
}

struct ReceiptCopyTests {
    private let now = Date(timeIntervalSince1970: 1_793_995_200) // 2026-11-06

    @Test func checksSayWhatWasFoundAndWhatWasnt() {
        let good = ReceiptReading(text: "", storeLine: "ILIOS CRAFTED GREEK", storeNameFound: true,
                                  orderDate: now.addingTimeInterval(-86_400), orderNumber: "A1B2")
        let lines = ReceiptCopy.checks(good, venueName: "Ilios", now: now)
        #expect(lines.map(\.ok) == [true, true, true])
        #expect(lines.last?.text == "Order #A1B2")

        let bad = ReceiptReading(text: "", storeNameFound: false, orderDate: now.addingTimeInterval(-12 * 86_400))
        #expect(ReceiptCopy.checks(bad, venueName: "Ilios", now: now).map(\.ok) == [false, false, false])
        #expect(ReceiptCopy.checks(bad, venueName: "Ilios", now: now)[0].text == "Can't find Ilios on it")
    }

    @Test func theResultSaysPointsOrWaiting() {
        let paid = ReceiptCopy.sentMessage(.init(claimId: "c", status: "approved", points: 10, venueBalance: 40), venueName: "Ilios")
        #expect(paid.title == "+10 points")
        #expect(paid.message == "You earned 10 points at Ilios for your delivery order. You have 40 points there.")
        let waiting = ReceiptCopy.sentMessage(.init(claimId: "c", status: "pending", points: nil, venueBalance: nil), venueName: "Ilios")
        #expect(waiting.title == "Sent to Ilios")
    }

    @Test func automaticOnlyPromisesPointsWhenEverythingChecksOut() {
        #expect(ReceiptCopy.sendNote(mode: "auto", venueName: "Ilios", allOK: true).hasPrefix("Everything checks out"))
        #expect(ReceiptCopy.sendNote(mode: "auto", venueName: "Ilios", allOK: false).hasPrefix("Ilios will take a look"))
        #expect(ReceiptCopy.sendNote(mode: "approve", venueName: "Ilios", allOK: true).hasPrefix("Ilios looks at each receipt"))
    }
}

struct ReceiptPushRouteTests {
    @Test func theStoreGoesToItsReceiptsTheCustomerToTheStore() {
        #expect(NotificationTapRouter.destination(for: ["type": "receipt_new", "venueId": "v1"]) == .venueReceipts(venueId: "v1"))
        #expect(NotificationTapRouter.destination(for: ["type": "receipt_result", "venueId": "v1", "placeId": "g1"]) == .place(id: "g1", showComments: nil))
        #expect(PendingLinkParser.parse("venue-receipts:v1") == .venueReceipts(venueId: "v1"))
    }
}

struct AdminAlertRouteTests {
    @Test func aPlaceToApproveOpensTheApprovalScreenOtherAlertsTheDashboard() {
        #expect(NotificationTapRouter.destination(for: ["type": "admin_alert", "key": "place-approval-g42"]) == .placeApprovals(placeId: "g42"))
        #expect(NotificationTapRouter.destination(for: ["type": "admin_alert", "key": "instagram_queue_empty"]) == .adminDashboard)
        #expect(NotificationTapRouter.destination(for: ["type": "admin_alert"]) == .adminDashboard)
        #expect(PendingLinkParser.parse("place-approvals:g42") == .placeApprovals(placeId: "g42"))
    }

    @Test func thePushedPlaceIsListedFirst() {
        let a = PlaceApprovalsViewController.PendingPlace(id: "a", name: "A", address: nil, category: nil, pendingSince: nil, mapUrl: nil, saves: 1, savedBy: ["Wes"])
        let b = PlaceApprovalsViewController.PendingPlace(id: "b", name: "B", address: "1 Main St", category: nil, pendingSince: nil, mapUrl: nil, saves: 2, savedBy: nil)
        #expect(PlaceApprovalCopy.ordered([a, b], focusId: "b").map(\.id) == ["b", "a"])
        #expect(PlaceApprovalCopy.ordered([a, b], focusId: "zz").map(\.id) == ["a", "b"])
        #expect(PlaceApprovalCopy.detail(b) == "1 Main St \u{00B7} 2 saves")
        #expect(PlaceApprovalCopy.done(name: "Ilios", approved: true, restored: 1) == "Ilios is public now. 1 save went back to the privacy people chose.")
    }
}

struct WelcomePeopleCopyTests {
    @Test func saysWhyEachPersonIsListed() {
        #expect(WelcomePeopleCopy.detail(reason: "Also loves Fresh Monkee", places: 45) == "Also loves Fresh Monkee \u{00B7} 45 places")
        #expect(WelcomePeopleCopy.detail(reason: "Near you", places: 1) == "Near you \u{00B7} 1 place")
        #expect(WelcomePeopleCopy.detail(reason: "⚡ Active this week", places: 70) == "70 places on their map")
        #expect(WelcomePeopleCopy.detail(reason: nil, places: 0) == "Just getting started")
        #expect(FirstFavoriteCopy.seeOnMapTitle(placeName: "Fresh Monkee") == "See Fresh Monkee on your map")
    }
}

struct SubscriptionMoveTests {
    @Test func namesTheOtherAccountAndDecodesTheFlag() throws {
        #expect(SubscriptionMoveCopy.message(emailHint: "s•••@gmail.com").contains("your other FavCircles account (s•••@gmail.com)"))
        let json = #"{"status":"none","linkedElsewhere":true,"linkedEmailHint":"s•••@gmail.com","autoRenewEnabled":false}"#
        let info = try JSONDecoder().decode(SubscriptionInfo.self, from: Data(json.utf8))
        #expect(info.linkedElsewhere == true)
        #expect(info.status == .none)
    }
}
