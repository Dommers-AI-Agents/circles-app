import Foundation

/// What a delivery receipt says, read from the lines the phone's text
/// recognition found (2026-11-06: points for DoorDash / Uber Eats orders).
/// The server checks again; this is what the customer sees before sending.
struct ReceiptReading: Equatable {
    var text: String
    /// The line naming the store, when one does
    var storeLine: String?
    /// The store's name is on it
    var storeNameFound: Bool
    var orderDate: Date?
    var orderNumber: String?
    var deliveryApp: String?
    var total: String?

    /// "2026-11-05", as the server reads dates
    var orderDay: String? {
        guard let orderDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: orderDate)
    }

    var body: [String: Any] {
        ["text": String(text.prefix(4000)), "storeLine": storeLine ?? NSNull(), "orderDate": orderDay ?? NSNull(),
         "orderNumber": orderNumber ?? NSNull(), "deliveryApp": deliveryApp ?? NSNull(), "total": total ?? NSNull()]
    }
}

enum ReceiptReader {
    /// Receipts earn for this many days after the order (server: receiptClaims MAX_AGE_DAYS)
    static let maxAgeDays = 7

    private static let apps: [(needle: String, name: String)] = [
        ("doordash", "DoorDash"), ("uber eats", "Uber Eats"), ("ubereats", "Uber Eats"), ("grubhub", "Grubhub"),
        ("postmates", "Postmates"), ("seamless", "Seamless"), ("caviar", "Caviar"), ("instacart", "Instacart")
    ]

    /// Words too common in store names to identify one (the server keeps the full list)
    private static let generic: Set<String> = [
        "the", "and", "cafe", "coffee", "bar", "grill", "kitchen", "restaurant", "pizza", "bakery", "deli",
        "house", "market", "crafted", "greek", "italian", "mexican", "thai", "sushi", "taco", "tacos", "burger"
    ]

    static func read(lines: [String], venueName: String, now: Date = Date()) -> ReceiptReading {
        let clean = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = clean.joined(separator: "\n")
        let folded = fold(text)

        let app = apps.first { folded.contains($0.needle) }?.name
        let nameWords = words(venueName)
        let key = nameWords.first { $0.count >= 3 && !generic.contains($0) } ?? nameWords.first { $0.count >= 3 }
        let storeLine = key.flatMap { k in clean.first { words($0).contains(k) } }

        return ReceiptReading(
            text: text,
            storeLine: storeLine,
            storeNameFound: storeLine != nil,
            orderDate: orderDate(in: text, now: now),
            orderNumber: orderNumber(in: clean),
            deliveryApp: app,
            total: total(in: clean)
        )
    }

    /// "Order #A1B2-C3D4", "Order ID: 3F2A1", "Order Number 123456789" → the number
    static func orderNumber(in lines: [String]) -> String? {
        let pattern = #"(?i)\border\s*(?:#|no\.?|number|id)?\s*[:#]?\s*#?\s*([A-Z0-9][A-Z0-9-]{3,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            for match in regex.matches(in: line, range: range) {
                guard let r = Range(match.range(at: 1), in: line) else { continue }
                let candidate = String(line[r])
                // "Order details", "Order total" aren't numbers
                if candidate.rangeOfCharacter(from: .decimalDigits) != nil { return candidate }
            }
        }
        return nil
    }

    /// The newest written date (a month name or 11/5), not in the future. A
    /// time alone ("7:42 PM") isn't a date.
    static func orderDate(in text: String, now: Date) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let written = try? NSRegularExpression(pattern: #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}|\b\d{1,2}/\d{1,2}(/\d{2,4})?\b"#)
        else { return nil }
        let latest = now.addingTimeInterval(86_400)
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match -> Date? in
            guard var date = match.date, let r = Range(match.range, in: text) else { return nil }
            // "November 5" with no year can read as next November
            if date > latest, let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: date) { date = lastYear }
            guard date <= latest else { return nil }
            let phrase = String(text[r])
            return written.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) == nil ? nil : date
        }.max()
    }

    /// "Total $23.45" → "$23.45" (the last total line: subtotals come first)
    static func total(in lines: [String]) -> String? {
        guard let money = try? NSRegularExpression(pattern: #"\$\s?\d+(?:[.,]\d{2})?"#) else { return nil }
        for line in lines.reversed() where fold(line).contains("total") && !fold(line).contains("subtotal") {
            if let m = money.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let r = Range(m.range, in: line) {
                return String(line[r]).replacingOccurrences(of: " ", with: "")
            }
        }
        return nil
    }

    /// Too old to earn (the server refuses these)
    static func isTooOld(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return date < now.addingTimeInterval(-Double(maxAgeDays) * 86_400 - 43_200)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US")).lowercased()
    }

    private static func words(_ s: String) -> [String] {
        fold(s).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
