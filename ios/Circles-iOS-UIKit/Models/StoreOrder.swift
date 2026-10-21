import Foundation

/// An order-ahead order (2026-10-20): from a store's full menu, pickup only,
/// paid at the counter. The customer and the store's team see the same one.
struct StoreOrder: Codable, Equatable {
    struct Line: Codable, Equatable {
        let itemId: String
        let name: String
        let section: String?
        let price: String?
        let qty: Int
        let note: String?
    }
    struct Pickup: Codable, Equatable {
        let asap: Bool
        let at: String?
    }

    let orderId: String
    /// The store's own team trying it ("Try it as a customer")
    let test: Bool?
    let venueId: String
    let venueName: String
    let globalPlaceId: String?
    let customerId: String
    let customerName: String
    let lines: [Line]
    let note: String?
    let pickup: Pickup
    let estimate: Double?
    let estimateIsPartial: Bool
    /// placed · accepted · ready · picked_up · declined · cancelled · expired
    let status: String
    let statusLabel: String
    let readyAt: String?
    let declineReason: String?
    let createdAt: String
    let updatedAt: String?

    var isOpen: Bool { ["placed", "accepted", "ready"].contains(status) }
    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } }
    var summary: String { lines.map { "\($0.qty)\u{00D7} \($0.name)" }.joined(separator: ", ") }
}

/// Whether a store takes orders in the app, and its usual prep time
struct StoreOrdering: Codable, Equatable {
    var enabled: Bool
    var leadMinutes: Int
    var note: String?

    init(enabled: Bool = false, leadMinutes: Int = 15, note: String? = nil) {
        self.enabled = enabled; self.leadMinutes = leadMinutes; self.note = note
    }
    enum CodingKeys: String, CodingKey { case enabled, leadMinutes, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        leadMinutes = (try? c.decode(Int.self, forKey: .leadMinutes)) ?? 15
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }
}
