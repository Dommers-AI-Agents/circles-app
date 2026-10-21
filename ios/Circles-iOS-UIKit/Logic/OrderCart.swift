import Foundation

/// What the customer is about to order (pure). The server prices the order
/// from the store's menu; the estimate here is only what the screen shows
/// ("About $32 · pay at pickup"), worked out the same way.
struct OrderCart: Equatable {
    struct Line: Equatable {
        let itemId: String
        let name: String
        let price: String?
        var qty: Int
        var note: String?
    }

    static let maxQty = 20
    static let maxLines = 50

    private(set) var lines: [Line] = []

    var isEmpty: Bool { lines.isEmpty }
    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } }

    func quantity(of itemId: String) -> Int { lines.first { $0.itemId == itemId }?.qty ?? 0 }

    mutating func add(_ item: StorefrontMenuItem) {
        if let i = lines.firstIndex(where: { $0.itemId == item.id }) {
            lines[i].qty = min(Self.maxQty, lines[i].qty + 1)
        } else if lines.count < Self.maxLines {
            lines.append(Line(itemId: item.id, name: item.name, price: item.price, qty: 1, note: nil))
        }
    }

    /// 0 removes the line
    mutating func setQuantity(_ qty: Int, for itemId: String) {
        guard let i = lines.firstIndex(where: { $0.itemId == itemId }) else { return }
        if qty <= 0 { lines.remove(at: i) } else { lines[i].qty = min(Self.maxQty, qty) }
    }

    mutating func setNote(_ note: String?, for itemId: String) {
        guard let i = lines.firstIndex(where: { $0.itemId == itemId }) else { return }
        let clean = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lines[i].note = clean.isEmpty ? nil : String(clean.prefix(200))
    }

    /// "16" / "$18.50" read as numbers; "MP", "8 / 14" don't (priced at the counter)
    static func priceValue(_ price: String?) -> Double? {
        guard let raw = price?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        var s = raw.lowercased()
        if s.hasPrefix("$") { s.removeFirst() }
        s = s.replacingOccurrences(of: "usd", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard s.range(of: #"^\d{1,4}(\.\d{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Double(s)
    }

    /// (total of the priced lines, whether some lines have no plain price)
    var estimate: (total: Double, partial: Bool) {
        var total = 0.0, partial = false
        for line in lines {
            if let v = Self.priceValue(line.price) { total += v * Double(line.qty) } else { partial = true }
        }
        return ((total * 100).rounded() / 100, partial)
    }

    /// "About $32.00" / "About $32.00 + items priced at the counter" / nil
    static func estimateText(total: Double?, partial: Bool) -> String? {
        guard let total, total > 0 else { return partial ? "Priced at the counter" : nil }
        let money = String(format: "$%.2f", total)
        return partial ? "About \(money) + items priced at the counter" : "About \(money)"
    }

    var requestItems: [[String: Any]] {
        lines.map { line -> [String: Any] in
            var row: [String: Any] = ["itemId": line.itemId, "qty": line.qty]
            if let note = line.note { row["note"] = note }
            return row
        }
    }
}
