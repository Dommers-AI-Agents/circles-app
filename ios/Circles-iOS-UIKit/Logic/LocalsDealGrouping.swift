import Foundation

/// The Locals tab's store deals, one row per store (Wes, 2026-11-05: "if a
/// store has 5 reward options, they don't take up the whole screen"). A store
/// with one deal is a plain row; a store with more is a header row that opens
/// to show each of them, like grouped activity. Stores keep the server's
/// order (saved first, then nearest) and deals keep theirs.
enum LocalsDealGrouping {
    enum Row<Item> {
        /// The store's only deal
        case single(Item)
        /// A store with several deals: all of them, and whether they show
        case store(key: String, items: [Item], isExpanded: Bool)
        /// One of an open store's deals, under its header
        case deal(Item)
    }

    /// - Parameters:
    ///   - key: the store an item belongs to
    ///   - expanded: stores opened by a tap
    ///   - expandAll: every store open (a search shows its matches)
    static func rows<Item>(_ items: [Item], key: (Item) -> String,
                           expanded: Set<String>, expandAll: Bool = false) -> [Row<Item>] {
        var order: [String] = []
        var byStore: [String: [Item]] = [:]
        for item in items {
            let store = key(item)
            if byStore[store] == nil { order.append(store) }
            byStore[store, default: []].append(item)
        }
        return order.flatMap { store -> [Row<Item>] in
            let deals = byStore[store] ?? []
            guard deals.count > 1 else { return deals.map { .single($0) } }
            let open = expandAll || expanded.contains(store)
            return [.store(key: store, items: deals, isExpanded: open)] + (open ? deals.map { .deal($0) } : [])
        }
    }

    /// The header's line under the store name: "Free drip coffee + 4 more"
    static func summary(first: String, count: Int) -> String {
        count > 1 ? "\(first) + \(count - 1) more" : first
    }
}
