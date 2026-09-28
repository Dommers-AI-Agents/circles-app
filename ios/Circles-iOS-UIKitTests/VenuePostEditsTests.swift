import Testing
import Foundation
@testable import Circles_iOS

/// Offer and announcement forms on the store-owner page.
struct VenuePostEditsTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: - Offers

    @Test func offerNeedsTitleAndPositivePoints() {
        #expect(VenueOfferEdit(title: "  ", pointsText: "100").problem?.hasPrefix("Add what the customer gets") == true)
        #expect(VenueOfferEdit(title: "Coffee", pointsText: "").problem == "Points must be a whole number above 0.")
        #expect(VenueOfferEdit(title: "Coffee", pointsText: "0").problem != nil)
        #expect(VenueOfferEdit(title: "Coffee", pointsText: "12.5").problem != nil)
        #expect(VenueOfferEdit(title: "Coffee", pointsText: " 100 ").problem == nil)
    }

    @Test func offerEditSendsOnlyWhatChanged() {
        let offer = RewardOffer(offerId: "o1", title: "Free coffee", pointsCost: 100, active: true)
        var draft = VenueOfferEdit(offer: offer)
        #expect(draft.changes(from: offer).isEmpty)
        draft.pointsText = "150"
        draft.isActive = false
        #expect(draft.changes(from: offer) == .init(title: nil, pointsCost: 150, active: false))
        draft.title = " Free latte "
        #expect(draft.changes(from: offer).title == "Free latte")
    }

    @Test func offerTreatsMissingActiveAsActive() {
        let offer = RewardOffer(offerId: "o1", title: "Tea", pointsCost: 50, active: nil)
        #expect(VenueOfferEdit(offer: offer).isActive)
        #expect(VenueOfferEdit(offer: offer).changes(from: offer).isEmpty)
    }

    @Test func visitsHintRoundsUp() {
        #expect(VenueOfferEdit.visitsHint(pointsCost: 100, earnRate: 25) == "About 4 visits at 25 points each.")
        #expect(VenueOfferEdit.visitsHint(pointsCost: 110, earnRate: 25) == "About 5 visits at 25 points each.")
        #expect(VenueOfferEdit.visitsHint(pointsCost: 20, earnRate: 25) == "One visit earns it at 25 points a visit.")
        #expect(VenueOfferEdit.visitsHint(pointsCost: nil, earnRate: 25) == nil)
    }

    // MARK: - Announcements

    @Test func announcementNeedsHeadlineMessageAndFutureEnd() {
        let now = day("2026-09-28T12:00:00Z")
        #expect(VenueAnnouncementEdit(title: "", message: "x").problem(now: now, calendar: utc)?.hasPrefix("Add a headline") == true)
        #expect(VenueAnnouncementEdit(title: "Happy Hour", message: " ").problem(now: now, calendar: utc)?.hasPrefix("Add the details") == true)
        // Ending today is fine — it stays up through the end of the day
        #expect(VenueAnnouncementEdit(title: "HH", message: "3–5", endsOn: now).problem(now: now, calendar: utc) == nil)
        #expect(VenueAnnouncementEdit(title: "HH", message: "3–5", endsOn: day("2026-09-27T12:00:00Z")).problem(now: now, calendar: utc)?.hasPrefix("The end date has already passed") == true)
    }

    @Test func expiryIsTheLastSecondOfTheDay() {
        let draft = VenueAnnouncementEdit(title: "HH", message: "x", endsOn: day("2026-10-01T08:30:00Z"))
        #expect(draft.expiresAt(calendar: utc) == "2026-10-01T23:59:59Z")
        #expect(VenueAnnouncementEdit(title: "HH", message: "x").expiresAt(calendar: utc) == nil)
    }

    @Test func announcementEditSendsOnlyWhatChanged() {
        let existing = VenueAnnouncement(announcementId: "a1", title: "HH", message: "3–5", expiresAt: "2026-10-01T23:59:59Z", createdAt: nil)
        var draft = VenueAnnouncementEdit(announcement: existing)
        #expect(draft.changes(from: existing, calendar: utc).isEmpty)

        draft.endsOn = nil
        #expect(draft.changes(from: existing, calendar: utc) == .init(clearExpiry: true))

        draft.endsOn = day("2026-10-05T10:00:00Z")
        draft.message = "4–6"
        #expect(draft.changes(from: existing, calendar: utc) == .init(message: "4–6", expiresAt: "2026-10-05T23:59:59Z"))
    }
}
