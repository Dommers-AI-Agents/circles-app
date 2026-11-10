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
        #expect(order == [.glance, .placePage, .menuOrdering, .loyalty, .customers, .announcements, .codes, .team, .more])
    }

    @Test func glanceLeadsWithStatsThenInsights() {
        #expect(rows(L.Facts(), .glance) == [.statTiles, .fullStats, .insights, .activity])
        #expect(rows(L.Facts(hasStats: false), .glance) == [.fullStats, .insights, .activity])
        #expect(L.isBusiness(.insights))
        #expect(!L.isBusiness(.fullStats))
    }

    @Test func everyRowAppearsOnce() {
        for facts in [L.Facts(offerCount: 2, announcementCount: 2), L.Facts(orderingOn: true),
                      L.Facts(isVirtual: true, hasPlace: false), L.Facts(hasPlace: false)] {
            let all = L.sections(facts).flatMap(\.rows)
            for (i, row) in all.enumerated() {
                #expect(!all[(i + 1)...].contains(row), "\(row) is listed twice")
            }
        }
    }

    @Test func onlineStoreDropsWindowCounterHoursAndCover() {
        let facts = L.Facts(isVirtual: true, hasPlace: false)
        let all = L.sections(facts).flatMap(\.rows)
        #expect(!all.contains(.showRegisterCard))
        #expect(!all.contains(.replaceRegisterCard))
        #expect(!all.contains(.showWindowSticker))
        #expect(!all.contains(.orderPage))
        #expect(rows(facts, .codes) == [.loyaltyCodes])
        let page = rows(facts, .placePage) ?? []
        #expect(page == [.gallery, .storefrontButtons])
    }

    @Test func placePageIsTheFreeBasics() {
        #expect(rows(L.Facts(), .placePage) == [.viewPage, .details, .hours, .photos, .storefrontButtons])
        #expect(rows(L.Facts(hasPlace: false), .placePage) == [.gallery, .storefrontButtons])
        (rows(L.Facts(), .placePage) ?? []).forEach { #expect(!L.isBusiness($0)) }
    }

    @Test func menuAndOrderingSitTogether() {
        #expect(rows(L.Facts(), .menuOrdering) == [.fullMenu, .menu, .onlineOrdering, .waitlist, .orderPage])
        #expect(rows(L.Facts(isVirtual: true, hasPlace: false), .menuOrdering) == [.fullMenu, .menu, .onlineOrdering])
    }

    @Test func ordersLeadTheScreenOnlyWhileTheStoreTakesOrders() {
        let on = L.sections(L.Facts(orderingOn: true))
        #expect(on.first?.section == .ordersNow)
        #expect(on.first?.rows == [.orders])
        // Off: Online ordering is the way in; Orders opened the same screen
        #expect(L.sections(L.Facts()).first?.section == .glance)
        #expect(!L.sections(L.Facts()).flatMap(\.rows).contains(.orders))
        // The waitlist leads the screen too while it's on, and leaves "Menu & ordering"
        let waitlist = L.sections(L.Facts(orderingOn: true, waitlistOn: true))
        #expect(waitlist.first?.rows == [.orders, .waitlist])
        #expect(!(rows(L.Facts(waitlistOn: true), .menuOrdering) ?? []).contains(.waitlist))
        #expect(L.sections(L.Facts(waitlistOn: true)).first?.rows == [.waitlist])
        #expect(L.isBusiness(.waitlist))
    }

    @Test func rewardsCustomersAndCodesAreSeparate() {
        let facts = L.Facts(offerCount: 2, announcementCount: 1)
        #expect(rows(facts, .loyalty) == [.earnRate, .savePoints, .deliveryOrders, .automations, .referrals, .offer(0), .offer(1), .addOffer, .rewardsUsed])
        #expect(L.isBusiness(.automations))
        #expect(L.isBusiness(.referrals))
        #expect(rows(facts, .customers) == [.customers, .savers, .followers, .feedback])
        #expect(rows(facts, .codes) == [.showRegisterCard, .showWindowSticker, .nfcStickers, .loyaltyCodes, .emailStickers, .replaceRegisterCard])
        #expect(rows(facts, .announcements) == [.announcement(0), .addAnnouncement])
        #expect(rows(facts, .glance) == [.statTiles, .fullStats, .insights, .activity])
    }

    @Test func tilesOnlyWhenStatsArrived() {
        #expect(rows(L.Facts(hasStats: false), .glance)?.first == .fullStats)
        #expect(rows(L.Facts(), .glance)?.first == .statTiles)
    }

    @Test func freePlanKeepsTheBasics() {
        let free: [L.Row] = [.statTiles, .fullStats, .viewPage, .details, .hours, .photos, .storefrontButtons,
                             .showWindowSticker, .nfcStickers, .emailStickers, .contactName, .contactEmail, .managers,
                             .plan, .ownerGuide, .brandStorefront, .addBusiness]
        free.forEach { #expect(!L.isBusiness($0), "\($0) should be free") }
    }

    @Test func businessToolsAreLocked() {
        let paid: [L.Row] = [.savers, .followers, .activity, .menu, .fullMenu, .orders, .onlineOrdering, .orderPage, .gallery, .earnRate, .offer(0), .addOffer,
                             .showRegisterCard, .replaceRegisterCard, .loyaltyCodes, .rewardsUsed, .customers, .announcement(0), .addAnnouncement]
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
