import Foundation

/// Wording for the store's automatic nudges, owner side and customer side.
/// Pure — no UIKit. Never says "text" or "SMS": nudges go by push, or by
/// email when a push can't reach someone.
enum StoreAutomationsCopy {

    enum Kind: CaseIterable {
        case winBack, birthday, almostThere

        var title: String {
            switch self {
            case .winBack: return "Win-back"
            case .birthday: return "Birthday treat"
            case .almostThere: return "Almost there"
            }
        }

        var explanation: String {
            switch self {
            case .winBack:
                return "A customer who hasn't bought here in a while hears \"We miss you\" — with bonus points on their next visit if you add some."
            case .birthday:
                return "On their birthday, customers who earn here get a happy birthday from you — with bonus points on their next visit if you add some. They give us the date; you never see it."
            case .almostThere:
                return "When one more purchase reaches your cheapest reward, the customer is told exactly that."
            }
        }

        var hasBonus: Bool { self != .almostThere }
    }

    static let winBackDays = [14, 30, 60, 90]

    static func daysTitle(_ days: Int) -> String { "\(days) days" }

    static func winBackDetail(days: Int) -> String { "After \(days) days without a purchase" }

    /// "+50 bonus points on the next visit" / "No bonus, just the note"
    static func bonusLine(_ points: Int) -> String {
        points > 0 ? "+\(points) bonus points on the next visit" : "No bonus, just the note"
    }

    /// "Sent 12 · 5 came back" / "Nothing sent yet"
    static func statsLine(sent: Int, cameBack: Int) -> String {
        guard sent > 0 else { return "Nothing sent yet" }
        return "Sent \(sent) · \(cameBack) came back"
    }

    /// Manage Store row subtitle: which are on
    static func summary(_ settings: StoreAutomations) -> String {
        var on: [String] = []
        if settings.winBack.enabled { on.append("win-back") }
        if settings.birthday.enabled { on.append("birthday") }
        if settings.almostThere.enabled { on.append("almost there") }
        guard !on.isEmpty else { return "Off: automatic win-back, birthday and almost-there nudges" }
        return "On: " + on.joined(separator: ", ")
    }

    static let pageFooter = "Nudges go to each customer's phone, or by email when a push can't reach them. At most one per customer every two weeks, never to anyone you removed from rewards. Bonus points are paid on their next register scan, within 30 days."

    static let bonusPrompt = "Bonus points (0 for none)"

    /// The win-back's coupon row (2026-11-14)
    static let couponRowTitle = "Coupon"
    static func couponLine(_ title: String?) -> String {
        title.map { "\($0) · claimed for them with the note" } ?? "No coupon"
    }

    // MARK: Customer side

    static let birthdayRowTitle = "Birthday treats"
    static func birthdayRowDetail(_ birthday: String?) -> String {
        guard let birthday, let label = birthdayLabel(birthday) else { return "Stores you earn with can send a birthday reward" }
        return "Your birthday: \(label)"
    }

    static let birthdayExplanation = "Stores where you earn rewards can send you a happy birthday — sometimes with bonus points. Only the month and day are saved, and no store ever sees the date."

    /// "MM-DD" → "March 14"; nil when it isn't one
    static func birthdayLabel(_ value: String) -> String? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
        let months = DateFormatter().monthSymbols ?? []
        guard parts[0] - 1 < months.count else { return nil }
        return "\(months[parts[0] - 1]) \(parts[1])"
    }

    /// A picked date → "MM-DD" (the year is dropped)
    static func birthdayValue(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 1, parts.day ?? 1)
    }
}
