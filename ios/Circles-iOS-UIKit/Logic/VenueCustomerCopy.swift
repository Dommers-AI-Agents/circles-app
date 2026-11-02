import Foundation

/// The words for one row of the store's Customers list. Pure.
enum VenueCustomerCopy {

    /// "12 purchases · 2 rewards · 75 pts · last today 3:10 PM"
    static func detail(_ customer: VenueCustomer, calendar: Calendar = .current, now: Date = Date()) -> String {
        if customer.removed { return "Removed from your rewards" }
        var parts = [count(customer.purchases, "purchase"), count(customer.rewardsClaimed, "reward"), "\(customer.points) pts"]
        if let last = RewardTicketCopy.date(customer.lastScanAt) {
            parts.append("last \(RewardTicketCopy.dayAndTime(last, calendar: calendar, now: now))")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(n == 1 ? noun : noun + "s")"
    }
}
