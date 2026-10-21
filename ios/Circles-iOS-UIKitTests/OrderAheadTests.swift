import Foundation
import Testing
@testable import Circles_iOS

/// Order ahead from a store's menu, pay at pickup (2026-10-20): the cart,
/// its estimate, and where its pushes open.
struct OrderAheadTests {
    private let margherita = StorefrontMenuItem(id: "m", name: "Margherita", price: "16")
    private let diavola = StorefrontMenuItem(id: "d", name: "Diavola", price: "$18.50")
    private let vongole = StorefrontMenuItem(id: "v", name: "Vongole", price: "MP")

    @Test func addingAgainRaisesTheQuantityAndZeroRemovesTheLine() {
        var cart = OrderCart()
        cart.add(margherita); cart.add(margherita); cart.add(diavola)
        #expect(cart.quantity(of: "m") == 2)
        #expect(cart.itemCount == 3)
        cart.setQuantity(0, for: "d")
        #expect(cart.lines.map(\.itemId) == ["m"])
        cart.setQuantity(99, for: "m")
        #expect(cart.quantity(of: "m") == OrderCart.maxQty)
    }

    @Test func notesAreTrimmedAndBlankClearsThem() {
        var cart = OrderCart()
        cart.add(margherita)
        cart.setNote("  no basil  ", for: "m")
        #expect(cart.lines[0].note == "no basil")
        cart.setNote("   ", for: "m")
        #expect(cart.lines[0].note == nil)
    }

    @Test func theEstimateCountsPlainPricesAndSaysWhenSomeArePricedAtTheCounter() {
        var cart = OrderCart()
        cart.add(margherita); cart.add(margherita); cart.add(diavola)
        #expect(cart.estimate.total == 50.5)
        #expect(cart.estimate.partial == false)
        #expect(OrderCart.estimateText(total: cart.estimate.total, partial: false) == "About $50.50")
        cart.add(vongole)
        #expect(cart.estimate.partial == true)
        #expect(OrderCart.estimateText(total: 50.5, partial: true) == "About $50.50 + items priced at the counter")
        #expect(OrderCart.estimateText(total: 0, partial: true) == "Priced at the counter")
        #expect(OrderCart.priceValue("12,50") == 12.5)
        #expect(OrderCart.priceValue("8 / 14") == nil)
    }

    @Test func theRequestSendsIdsAndQuantitiesNotPrices() {
        var cart = OrderCart()
        cart.add(diavola)
        cart.setNote("well done", for: "d")
        let row = cart.requestItems[0]
        #expect(row["itemId"] as? String == "d")
        #expect(row["qty"] as? Int == 1)
        #expect(row["note"] as? String == "well done")
        #expect(row["price"] == nil)
    }

    @Test func orderPushesOpenTheOrderOrTheStoresOrders() {
        #expect(NotificationTapRouter.destination(for: ["type": "order_update", "orderId": "o1"]) == .storeOrder(id: "o1"))
        #expect(NotificationTapRouter.destination(for: ["type": "order_new", "orderId": "o1", "venueId": "v1"]) == .venueOrders(venueId: "v1"))
        #expect(PendingLinkParser.parse("order:o1") == .storeOrder(id: "o1"))
        #expect(PendingLinkParser.parse("venue-orders:v1") == .venueOrders(venueId: "v1"))
    }
}
