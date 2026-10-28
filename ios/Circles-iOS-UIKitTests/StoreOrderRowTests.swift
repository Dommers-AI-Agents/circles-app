import Testing
import Foundation
@testable import Circles_iOS

/// The customer's order as the place page and My Orders list it (2026-10-28).
struct StoreOrderRowTests {
    private func order(status: String, label: String, readyAt: String? = nil) throws -> StoreOrder {
        let json = """
        {"orderId": "o1", "venueId": "v1", "venueName": "Test Bakery", "customerId": "c", "customerName": "Wes",
         "lines": [{"itemId": "i", "name": "Croissant", "qty": 2}], "pickup": {"asap": true}, "estimateIsPartial": false,
         "status": "\(status)", "statusLabel": "\(label)", \(readyAt.map { "\"readyAt\": \"\($0)\"," } ?? "")
         "createdAt": "2026-10-28T16:00:00.000Z"}
        """
        return try JSONDecoder().decode(StoreOrder.self, from: Data(json.utf8))
    }

    @Test func statusLineAddsTheReadyTimeOnceAccepted() throws {
        #expect(try order(status: "placed", label: "Waiting for the store").statusLine(readyTime: nil) == "Waiting for the store")
        #expect(try order(status: "accepted", label: "Accepted", readyAt: "2026-10-28T16:40:00.000Z").statusLine(readyTime: "12:40 PM")
                == "Accepted \u{00B7} ready by 12:40 PM")
        #expect(try order(status: "ready", label: "Ready for pickup").statusLine(readyTime: "12:40 PM") == "Ready for pickup")
    }

    @Test func thePlacePageNeverLosesItsCardToABadOrder() throws {
        // by-place with the order in a shape this build can't read: the card decodes, the row is simply absent
        let json = #"{"venue": null, "myOrder": {"orderId": 7}}"#
        let data = try JSONDecoder().decode(PlaceVenueData.self, from: Data(json.utf8))
        #expect(data.myOrder == nil)
        // And a missing key is the usual nil
        let none = try JSONDecoder().decode(PlaceVenueData.self, from: Data(#"{"venue": null}"#.utf8))
        #expect(none.myOrder == nil)
        let good = try JSONDecoder().decode(PlaceVenueData.self, from: Data(("{\"venue\": null, \"myOrder\": " + String(decoding: try JSONEncoder().encode(try order(status: "placed", label: "Waiting for the store")), as: UTF8.self) + "}").utf8))
        #expect(good.myOrder?.venueName == "Test Bakery")
    }

    @Test func everyOpenOrderAtTheStoreComesThrough() throws {
        let one = String(decoding: try JSONEncoder().encode(try order(status: "ready", label: "Ready for pickup")), as: UTF8.self)
        let two = String(decoding: try JSONEncoder().encode(try order(status: "placed", label: "Waiting for the store")), as: UTF8.self)
        let data = try JSONDecoder().decode(PlaceVenueData.self, from: Data("{\"venue\": null, \"myOrders\": [\(two), \(one)]}".utf8))
        #expect(data.myOrders?.map(\.status) == ["placed", "ready"])
        // A server before the field: nil, and the page falls back to the single order
        #expect(try JSONDecoder().decode(PlaceVenueData.self, from: Data(#"{"venue": null}"#.utf8)).myOrders == nil)
    }
}
