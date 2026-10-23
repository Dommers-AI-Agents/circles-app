import Foundation

/// The words on the owner bar at the top of the owner's own store card
/// (2026-10-23): what needs them first (new orders), then how the store is
/// doing. Pure, so it's table-tested.
enum OwnerBarSummary {
    struct Input: Equatable {
        var orderingEnabled = false
        var newOrders = 0
        var saves = 0
        var visits = 0
        var premium = true
    }

    /// "2 new orders" / "No new orders" while ordering is on; otherwise the
    /// store's numbers lead ("14 saves · 3 visits"), since the card's header
    /// already says it's their store
    static func headline(_ input: Input) -> String {
        guard input.orderingEnabled else { return counts(input) }
        switch input.newOrders {
        case 0: return "No new orders"
        case 1: return "1 new order"
        default: return "\(input.newOrders) new orders"
        }
    }

    /// The line under it: the numbers (when orders led), then "Free plan"
    /// before Business; "Stats & insights" when there's nothing else to say
    static func detail(_ input: Input) -> String {
        var parts: [String] = input.orderingEnabled ? [counts(input)] : []
        if !input.premium { parts.append("Free plan") }
        return parts.isEmpty ? "Stats & insights" : parts.joined(separator: " \u{00B7} ")
    }

    private static func counts(_ input: Input) -> String {
        "\(input.saves) save\(input.saves == 1 ? "" : "s") \u{00B7} \(input.visits) visit\(input.visits == 1 ? "" : "s")"
    }

    /// New orders are what the owner should see first, in the accent colour
    static func needsAttention(_ input: Input) -> Bool {
        input.orderingEnabled && input.newOrders > 0
    }
}
