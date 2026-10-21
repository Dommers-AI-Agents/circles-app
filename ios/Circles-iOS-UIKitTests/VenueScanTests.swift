import Foundation
import Testing
@testable import Circles_iOS

/// Store-owner scans (2026-10-20): the full menu's editing rules, putting a
/// scanned hours sign or flyer into the editors, and the customer search.
struct VenueScanTests {
    private func item(_ name: String, _ price: String? = nil, unsure: Bool = false) -> StorefrontMenuItem {
        StorefrontMenuItem(name: name, price: price, unsure: unsure)
    }

    // MARK: Menu draft

    @Test func aSecondScanAddsOnlyNewItemsToMatchingSections() {
        var draft = MenuDraft(StorefrontMenu(sections: [
            StorefrontMenuSection(name: "Pizza", items: [item("Margherita", "16")])
        ]))
        draft.apply(scan: [
            StorefrontMenuSection(name: "PIZZA", items: [item("margherita", "16"), item("Diavola", "18", unsure: true)]),
            StorefrontMenuSection(name: "Dolci", items: [item("Tiramisù", "9")])
        ], merge: .add)
        #expect(draft.sections.map(\.name) == ["Pizza", "Dolci"])
        #expect(draft.sections[0].items.map(\.name) == ["Margherita", "Diavola"])
        #expect(draft.unsureCount == 1)
        #expect(draft.menu.source == "scan")
    }

    @Test func replacingStartsOverAndLimitsHold() {
        var draft = MenuDraft(StorefrontMenu(sections: [StorefrontMenuSection(name: "Old", items: [item("x")])]))
        let huge = StorefrontMenuSection(name: "All", items: (0..<450).map { item("Item \($0)") })
        draft.apply(scan: [huge], merge: .replace)
        #expect(draft.sections.map(\.name) == ["All"])
        #expect(draft.itemCount == MenuDraft.maxItems)
    }

    @Test func editingAnItemClearsCheckThisAndBlankNamesAreRefused() {
        var draft = MenuDraft(StorefrontMenu(sections: [StorefrontMenuSection(name: "Pasta", items: [item("Cacio e Pep", "17", unsure: true)])]))
        #expect(draft.setItem(section: 0, row: 0, name: "Cacio e Pepe", price: " $17 ", description: "") == true)
        #expect(draft.sections[0].items[0] == StorefrontMenuItem(id: draft.sections[0].items[0].id, name: "Cacio e Pepe", price: "$17"))
        #expect(draft.unsureCount == 0)
        #expect(draft.setItem(section: 0, row: nil, name: "   ", price: "5", description: nil) == false)
        #expect(draft.setItem(section: 0, row: nil, name: "Lasagna", price: nil, description: "Nonna's") == true)
        #expect(draft.sections[0].items.last?.description == "Nonna's")
    }

    @Test func movingAcrossSectionsAndEmptySectionsArentSaved() {
        var draft = MenuDraft(StorefrontMenu(sections: [
            StorefrontMenuSection(name: "A", items: [item("1"), item("2")]),
            StorefrontMenuSection(name: "B", items: [])
        ]))
        draft.moveItem(from: (0, 1), to: (1, 0))
        #expect(draft.sections[0].items.map(\.name) == ["1"])
        #expect(draft.sections[1].items.map(\.name) == ["2"])
        draft.deleteItem(section: 1, row: 0)
        #expect(draft.forSaving.sections.map(\.name) == ["A"])
        draft.confirmItem(section: 9, row: 9)   // out of range: no crash
    }

    @Test func savingSendsTheServersShape() throws {
        let menu = StorefrontMenu(sections: [StorefrontMenuSection(id: "s1", name: "Vino", items: [StorefrontMenuItem(id: "i1", name: "Prosecco", price: "12", tags: ["sparkling"])])], source: "scan")
        let body = menu.asBody
        #expect(body["source"] as? String == "scan")
        let section = try #require((body["sections"] as? [[String: Any]])?.first)
        let first = try #require((section["items"] as? [[String: Any]])?.first)
        #expect(first["name"] as? String == "Prosecco")
        #expect(first["price"] as? String == "12")
        #expect(first["unsure"] == nil)   // never saved
    }

    // MARK: Hours sign

    @Test func hoursFillOnlyWhatTheSignShows() {
        let base = VenueHoursDraft(existing: [(day: 3, open: "10:00", close: "18:00", isClosed: false)])
        let scan = HoursScanDraft(hours: [
            .init(day: 0, open: nil, close: nil, isClosed: true, unsure: false),
            .init(day: 1, open: "07:00", close: "15:00", isClosed: false, unsure: false),
            .init(day: 6, open: "08:00", close: nil, isClosed: false, unsure: true),
            .init(day: 3, open: nil, close: nil, isClosed: false, unsure: false)
        ], found: 3)
        let applied = VenueScanApply.hours(base, scan: scan)
        let byDay = Dictionary(uniqueKeysWithValues: applied.draft.days.map { ($0.day, $0) })
        #expect(byDay[0]?.isClosed == true)
        #expect(byDay[1]?.open == "07:00" && byDay[1]?.close == "15:00")
        #expect(byDay[6]?.open == "08:00")
        #expect(byDay[3]?.open == "10:00")         // not on the sign: unchanged
        #expect(applied.unsureDays == [6])
        #expect(applied.filled == 3)
    }

    // MARK: Flyer

    @Test func anEventFlyerFillsTheEventFields() throws {
        let flyer = FlyerScanDraft(title: "Trivia Night", message: "Teams of up to 6.",
                                   event: .init(localDate: "2026-10-30", localTime: "23:00", endTime: "01:00", isFree: true),
                                   expiresOn: nil, unsure: ["event_date"])
        let tz = try #require(TimeZone(identifier: "America/New_York"))
        let edit = VenueScanApply.announcement(flyer, into: VenueAnnouncementEdit(), timeZone: tz)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let start = try #require(edit.eventStart)
        let end = try #require(edit.eventEnd)
        #expect(edit.title == "Trivia Night")
        #expect(cal.component(.hour, from: start) == 23 && cal.component(.day, from: start) == 30)
        #expect(end > start)                       // past midnight: next day
        #expect(edit.eventIsFree == true)
        #expect(VenueScanApply.flyerCheckLine(flyer) == "Check the date: the photo was hard to read there.")
    }

    @Test func aSpecialWithAnEndDateIsNotAnEvent() {
        let flyer = FlyerScanDraft(title: "Happy Hour", message: "Half-price apps 3–6", event: nil, expiresOn: "2026-11-30", unsure: [])
        let edit = VenueScanApply.announcement(flyer, into: VenueAnnouncementEdit())
        #expect(edit.isEvent == false)
        #expect(edit.endsOn != nil)
        #expect(VenueScanApply.flyerCheckLine(flyer) == nil)
    }

    // MARK: Customer search

    @Test func searchMatchesEveryWordAcrossNameDescriptionTagsAndSection() {
        let menu = StorefrontMenu(sections: [
            StorefrontMenuSection(name: "Pizza", items: [StorefrontMenuItem(name: "Margherita", price: "16", description: "basil", tags: ["vegetarian"]),
                                                         StorefrontMenuItem(name: "Diavola", price: "18", tags: ["spicy"])]),
            StorefrontMenuSection(name: "Dolci", items: [StorefrontMenuItem(name: "Tiramisù", price: "9")])
        ])
        #expect(PlaceMenuViewController.filter(menu, query: "vegetarian pizza").flatMap { $0.items.map(\.name) } == ["Margherita"])
        #expect(PlaceMenuViewController.filter(menu, query: "").count == 2)
        #expect(PlaceMenuViewController.filter(menu, query: "sushi").isEmpty)
    }
}
