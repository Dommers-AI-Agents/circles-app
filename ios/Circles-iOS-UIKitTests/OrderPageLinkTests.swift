import Testing
import Foundation
@testable import Circles_iOS

/// The store's web page link and a web guest's order as the app decodes it (2026-10-28).
struct OrderPageLinkTests {

    @Test func orderPageLinkLivesOnTheOrderingHost() {
        #expect(ShareLinks.orderPage(slug: "wooden-robot-brewery").absoluteString == "https://order.favcircles.com/wooden-robot-brewery")
    }

    @Test func aWebGuestOrderDecodesWithItsContactForTheStore() throws {
        let json = """
        {"orderId":"o1","venueId":"v1","venueName":"Test Bakery","customerId":"guest","customerName":"Ana Ruiz","channel":"web",
         "customer":{"name":"Ana Ruiz","phone":"+17045550100","email":null},
         "lines":[{"itemId":"c","name":"Croissant","price":"4","qty":2}],"pickup":{"asap":true,"at":null},
         "estimate":8,"estimateIsPartial":false,"status":"placed","statusLabel":"Waiting for the store","createdAt":"2026-10-28T12:00:00.000Z"}
        """
        let order = try JSONDecoder().decode(StoreOrder.self, from: Data(json.utf8))
        #expect(order.isWeb)
        #expect(order.customer?.phone == "+17045550100")
        #expect(order.customerId == "guest")
        #expect(order.isOpen)
    }

    @Test func anAppOrderWithoutTheNewFieldsStillDecodes() throws {
        let json = """
        {"orderId":"o2","venueId":"v1","venueName":"Test Bakery","customerId":"u1","customerName":"Bo","lines":[],
         "pickup":{"asap":false,"at":"2026-10-28T13:00:00.000Z"},"estimate":null,"estimateIsPartial":false,"status":"ready","statusLabel":"Ready","createdAt":"2026-10-28T12:00:00.000Z"}
        """
        let order = try JSONDecoder().decode(StoreOrder.self, from: Data(json.utf8))
        #expect(!order.isWeb)
        #expect(order.customer == nil)
    }

    @Test func storefrontCarriesItsOrderingPage() throws {
        let json = """
        {"offeringsLabel":"Menu","offerings":null,"menu":null,"ordering":{"enabled":true,"leadMinutes":20,"note":null},"actions":null,"gallery":[],
         "orderingPage":{"slug":"test-bakery-demo","url":"https://order.favcircles.com/test-bakery-demo"}}
        """
        let sf = try JSONDecoder().decode(VenueStorefront.self, from: Data(json.utf8))
        #expect(sf.orderingPage == StorefrontOrderingPage(slug: "test-bakery-demo", url: "https://order.favcircles.com/test-bakery-demo"))
    }
}
