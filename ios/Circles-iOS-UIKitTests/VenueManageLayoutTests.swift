import Testing
import Foundation
@testable import Circles_iOS

/// The store-owner page: grouping, online-store trimming, Business locks, hours.
struct VenueManageLayoutTests {

    private typealias L = VenueManageLayout

    private func rows(_ facts: L.Facts, _ section: L.Section) -> [L.Row]? {
        L.sections(facts).first { $0.section == section }?.rows
    }

    @Test func physicalStoreShowsEveryGroupInOrder() {
        let order = L.sections(L.Facts()).map(\.section)
        #expect(order == [.glance, .placePage, .loyalty, .announcements, .windowSticker, .team, .more])
    }

    @Test func onlineStoreDropsWindowCounterHoursAndCover() {
        let facts = L.Facts(isVirtual: true, hasPlace: false)
        #expect(!L.sections(facts).map(\.section).contains(.windowSticker))
        let loyalty = rows(facts, .loyalty) ?? []
        #expect(!loyalty.contains(.showRegisterCard))
        #expect(!loyalty.contains(.replaceRegisterCard))
        #expect(loyalty.contains(.loyaltyCodes))
        let page = rows(facts, .placePage) ?? []
        #expect(!page.contains(.hours))
        #expect(!page.contains(.coverPhoto))
        #expect(page.contains(.storefrontButtons))
    }

    @Test func noPlaceRecordHidesPlaceRows() {
        let page = rows(L.Facts(hasPlace: false), .placePage) ?? []
        #expect(page == [.storefrontButtons, .menu, .gallery])
    }

    @Test func offersAndAnnouncementsListThenAdd() {
        let facts = L.Facts(offerCount: 2, announcementCount: 1)
        #expect(rows(facts, .loyalty) == [.earnRate, .offer(0), .offer(1), .addOffer, .showRegisterCard, .replaceRegisterCard, .loyaltyCodes])
        #expect(rows(facts, .announcements) == [.announcement(0), .addAnnouncement])
    }

    @Test func tilesOnlyWhenStatsArrived() {
        #expect(rows(L.Facts(hasStats: false), .glance)?.first == .fullStats)
        #expect(rows(L.Facts(), .glance)?.first == .statTiles)
    }

    @Test func freePlanKeepsTheBasics() {
        let free: [L.Row] = [.statTiles, .fullStats, .viewPage, .hours, .coverPhoto, .storefrontButtons,
                             .showWindowSticker, .emailStickers, .contactName, .contactEmail, .managers,
                             .plan, .ownerGuide, .brandStorefront, .addBusiness]
        free.forEach { #expect(!L.isBusiness($0), "\($0) should be free") }
    }

    @Test func businessToolsAreLocked() {
        let paid: [L.Row] = [.savers, .followers, .activity, .menu, .gallery, .earnRate, .offer(0), .addOffer,
                             .showRegisterCard, .replaceRegisterCard, .loyaltyCodes, .announcement(0), .addAnnouncement]
        paid.forEach { #expect(L.isBusiness($0), "\($0) should need Business") }
    }

    // MARK: - Copy

    @Test func statTilesDefaultMissingCountersToZero() {
        let tiles = VenueManageCopy.statTiles(AdminVenueStats(scans: nil, signups: nil, saves: 12, visits: nil, redemptions: 3, followers: nil))
        #expect(tiles.map(\.title) == ["Visits", "Redeemed", "Saves", "Followers"])
        #expect(tiles.map(\.value) == [0, 3, 12, 0])
    }

    @Test func managersLineReadsNaturally() {
        #expect(VenueManageCopy.managersLine(0) == "Invite someone to run this store with you")
        #expect(VenueManageCopy.managersLine(1) == "1 manager helps run this store")
        #expect(VenueManageCopy.managersLine(3) == "3 managers help run this store")
    }

    // MARK: - Hours

    @Test func hoursSeedFromExistingAndFillGaps() {
        let draft = VenueHoursDraft(existing: [
            (day: 1, open: "8:30", close: "18:00", isClosed: false),
            (day: 0, open: nil, close: nil, isClosed: true)
        ])
        #expect(draft.days.map(\.day) == [1, 2, 3, 4, 5, 6, 0])
        #expect(draft.days[0] == .init(day: 1, isClosed: false, open: "08:30", close: "18:00"))
        #expect(draft.days[1] == .init(day: 2, isClosed: false, open: "09:00", close: "17:00"))
        #expect(draft.days[6].isClosed)
    }

    @Test func hoursBodyAlwaysHasSevenDaysSundayFirst() {
        var draft = VenueHoursDraft(existing: [])
        draft.days[6].isClosed = true // Sunday
        let week = draft.requestBody["openingHours"] as? [[String: Any]] ?? []
        #expect(week.count == 7)
        #expect(week.map { $0["day"] as? Int } == [0, 1, 2, 3, 4, 5, 6])
        #expect(week[0]["isClosed"] as? Bool == true)
        #expect(week[0]["open"] is NSNull)
        #expect(week[1]["open"] as? String == "09:00")
    }

    @Test func hoursProblems() {
        var draft = VenueHoursDraft(existing: [])
        #expect(draft.problem == nil)
        draft.days[0].close = draft.days[0].open
        #expect(draft.problem == "Monday opens and closes at the same time.")
        for i in draft.days.indices { draft.days[i].isClosed = true }
        #expect(draft.problem?.hasPrefix("Every day is marked closed") == true)
    }

    @Test func normalizesTimes() {
        #expect(VenueHoursDraft.normalized("9:05") == "09:05")
        #expect(VenueHoursDraft.normalized("24:00") == nil)
        #expect(VenueHoursDraft.normalized("noon") == nil)
    }
}
