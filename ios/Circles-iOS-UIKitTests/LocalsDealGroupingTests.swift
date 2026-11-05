import Foundation
import Testing
@testable import Circles_iOS

/// Locals deals, one row per store (Wes, 2026-11-05)
struct LocalsDealGroupingTests {
    private typealias Deal = (store: String, title: String)
    private let deals: [Deal] = [("sals", "Free drip coffee"), ("sals", "Free muffin"), ("mon", "BOGO"),
                                 ("sals", "10% off"), ("tea", "Free tea"), ("tea", "Half-price boba")]

    private func shape(_ rows: [LocalsDealGrouping.Row<Deal>]) -> [String] {
        rows.map {
            switch $0 {
            case .single(let d): return "single:\(d.title)"
            case .store(let key, let items, let open): return "store:\(key):\(items.count):\(open ? "open" : "shut")"
            case .deal(let d): return "deal:\(d.title)"
            }
        }
    }

    @Test func storesInFirstSeenOrderOneRowEachWhenShut() {
        let rows = LocalsDealGrouping.rows(deals, key: { $0.store }, expanded: [])
        #expect(shape(rows) == ["store:sals:3:shut", "single:BOGO", "store:tea:2:shut"])
    }

    @Test func openStoreListsItsDealsUnderItInOrder() {
        let rows = LocalsDealGrouping.rows(deals, key: { $0.store }, expanded: ["sals"])
        #expect(shape(rows) == ["store:sals:3:open", "deal:Free drip coffee", "deal:Free muffin", "deal:10% off",
                                "single:BOGO", "store:tea:2:shut"])
    }

    @Test func searchOpensEveryStore() {
        let rows = LocalsDealGrouping.rows(deals, key: { $0.store }, expanded: [], expandAll: true)
        #expect(shape(rows).filter { $0.hasPrefix("deal:") }.count == 5)
        #expect(LocalsDealGrouping.rows([Deal](), key: { $0.store }, expanded: []).isEmpty)
    }

    @Test func headerSummary() {
        #expect(LocalsDealGrouping.summary(first: "Free drip coffee", count: 5) == "Free drip coffee + 4 more")
        #expect(LocalsDealGrouping.summary(first: "BOGO", count: 1) == "BOGO")
    }
}
