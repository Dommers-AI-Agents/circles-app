import Foundation

/// The full menu as the owner edits it (pure). Everything the editor does to
/// the menu goes through here so the rules — limits, what clears "Check
/// this", how a second scan joins the first — are tested in one place.
struct MenuDraft: Equatable {
    static let maxSections = 30
    static let maxItems = 400

    var menu: StorefrontMenu

    init(_ menu: StorefrontMenu = StorefrontMenu()) { self.menu = menu }

    var sections: [StorefrontMenuSection] { menu.sections }
    var itemCount: Int { menu.itemCount }
    /// Items the scan wasn't sure about and the owner hasn't touched
    var unsureCount: Int { menu.sections.reduce(0) { $0 + $1.items.filter(\.unsure).count } }

    /// How a new scan joins what's there
    enum ScanMerge { case replace, add }

    /// A scan's sections replace the menu, or join it: a section with the
    /// same name (any case) gets the new items it doesn't already have.
    mutating func apply(scan: [StorefrontMenuSection], merge: ScanMerge) {
        menu.source = "scan"
        guard merge == .add else { menu.sections = scan; clampToLimits(); return }
        for incoming in scan {
            if let i = menu.sections.firstIndex(where: { Self.same($0.name, incoming.name) }) {
                let have = Set(menu.sections[i].items.map { Self.key($0.name) })
                menu.sections[i].items += incoming.items.filter { !have.contains(Self.key($0.name)) }
            } else {
                menu.sections.append(incoming)
            }
        }
        clampToLimits()
    }

    mutating func addSection(named name: String) -> Int? {
        let clean = Self.trimmed(name, 60)
        guard !clean.isEmpty, menu.sections.count < Self.maxSections else { return nil }
        menu.sections.append(StorefrontMenuSection(name: clean))
        return menu.sections.count - 1
    }

    mutating func renameSection(_ index: Int, to name: String) {
        let clean = Self.trimmed(name, 60)
        guard menu.sections.indices.contains(index), !clean.isEmpty else { return }
        menu.sections[index].name = clean
    }

    mutating func deleteSection(_ index: Int) {
        guard menu.sections.indices.contains(index) else { return }
        menu.sections.remove(at: index)
    }

    mutating func moveSection(_ index: Int, by offset: Int) {
        let target = index + offset
        guard menu.sections.indices.contains(index), menu.sections.indices.contains(target) else { return }
        menu.sections.swapAt(index, target)
    }

    /// Adds or replaces an item from the owner's three fields. A blank name
    /// is refused (returns false). Editing an item clears its "Check this".
    @discardableResult
    mutating func setItem(section: Int, row: Int?, name: String, price: String?, description: String?) -> Bool {
        let cleanName = Self.trimmed(name, 80)
        guard menu.sections.indices.contains(section), !cleanName.isEmpty else { return false }
        let cleanPrice = Self.trimmed(price ?? "", 20)
        let cleanDescription = Self.trimmed(description ?? "", 300)
        if let row, menu.sections[section].items.indices.contains(row) {
            var item = menu.sections[section].items[row]
            item.name = cleanName
            item.price = cleanPrice.isEmpty ? nil : cleanPrice
            item.description = cleanDescription.isEmpty ? nil : cleanDescription
            item.unsure = false
            menu.sections[section].items[row] = item
        } else {
            guard itemCount < Self.maxItems else { return false }
            menu.sections[section].items.append(StorefrontMenuItem(
                name: cleanName, price: cleanPrice.isEmpty ? nil : cleanPrice,
                description: cleanDescription.isEmpty ? nil : cleanDescription))
        }
        return true
    }

    /// "Looks right": clears the flag without changing the item
    mutating func confirmItem(section: Int, row: Int) {
        guard menu.sections.indices.contains(section), menu.sections[section].items.indices.contains(row) else { return }
        menu.sections[section].items[row].unsure = false
    }

    mutating func deleteItem(section: Int, row: Int) {
        guard menu.sections.indices.contains(section), menu.sections[section].items.indices.contains(row) else { return }
        menu.sections[section].items.remove(at: row)
    }

    /// Drag to reorder, across sections too
    mutating func moveItem(from: (section: Int, row: Int), to: (section: Int, row: Int)) {
        guard menu.sections.indices.contains(from.section), menu.sections[from.section].items.indices.contains(from.row),
              menu.sections.indices.contains(to.section) else { return }
        let item = menu.sections[from.section].items.remove(at: from.row)
        let row = min(max(0, to.row), menu.sections[to.section].items.count)
        menu.sections[to.section].items.insert(item, at: row)
    }

    /// What's sent: empty sections dropped (the server would drop them too)
    var forSaving: StorefrontMenu {
        var out = menu
        out.sections = menu.sections.filter { !$0.items.isEmpty }
        return out
    }

    private mutating func clampToLimits() {
        if menu.sections.count > Self.maxSections { menu.sections = Array(menu.sections.prefix(Self.maxSections)) }
        var left = Self.maxItems
        for i in menu.sections.indices {
            let keep = min(left, menu.sections[i].items.count)
            menu.sections[i].items = Array(menu.sections[i].items.prefix(keep))
            left -= keep
        }
    }

    private static func trimmed(_ s: String, _ max: Int) -> String {
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }
    private static func key(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }
    private static func same(_ a: String, _ b: String) -> Bool { key(a) == key(b) }
}
