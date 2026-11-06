import Foundation
import Testing
@testable import Circles_iOS

struct PlaceActionPlannerTests {
    private static func group(_ id: String, _ title: String, order: Int) -> PartnerActionGroup {
        let json = """
        {"id":"\(id)","title":"\(title)","icon":"car","order":\(order),
         "providers":[{"id":"p","title":"P","webUrlTemplate":"https://example.com/{name}"}]}
        """
        return try! JSONDecoder().decode(PartnerActionGroup.self, from: Data(json.utf8))
    }
    private static let catalog = [group("delivery", "Delivery", order: 10),
                                  group("reserve", "Reservations", order: 20),
                                  group("ride", "Ride", order: 30)]

    private func titles(_ planner: PlaceActionPlanner) -> [String] { planner.actions().map(\.title) }

    /// Ilios: a counter-service Greek restaurant, Google silent on everything
    @Test func iliosGetsMenuAndDeliveryNotReservations() {
        let planner = PlaceActionPlanner(category: .restaurant, website: "http://www.ilioscraftedgreek.com/",
                                         distanceMeters: 1_200, partnerGroups: Self.catalog)
        #expect(titles(planner) == ["Menu", "Delivery"])
        #expect(planner.actions().first?.kind == .link("http://www.ilioscraftedgreek.com/"))
    }

    @Test func rideOnlyWhenFarAway() {
        var planner = PlaceActionPlanner(category: .restaurant, distanceMeters: 20_000, partnerGroups: Self.catalog)
        #expect(titles(planner) == ["Delivery", "Ride"])
        planner.distanceMeters = nil
        #expect(titles(planner) == ["Delivery"])
    }

    @Test func reservationsWhenGoogleSaysSoOrItsUpscale() {
        var planner = PlaceActionPlanner(category: .restaurant, reservable: true, website: "stir.com",
                                         partnerGroups: Self.catalog)
        #expect(titles(planner) == ["Menu", "Reservations", "Delivery"])
        planner.reservable = nil
        planner.priceLevel = .expensive
        #expect(titles(planner) == ["Menu", "Delivery", "Reservations"])
        planner.reservable = false
        #expect(titles(planner) == ["Menu", "Delivery"])
    }

    @Test func deliveryHidesOnlyWhenGoogleSaysNoToBoth() {
        let planner = PlaceActionPlanner(category: .restaurant, delivery: false, takeout: false, partnerGroups: Self.catalog)
        #expect(titles(planner).isEmpty)
        let takeout = PlaceActionPlanner(category: .restaurant, delivery: false, takeout: true, partnerGroups: Self.catalog)
        #expect(titles(takeout) == ["Delivery"])
    }

    @Test func menuOpensOrderingFirstThenTheOwnersLinkThenTheWebsite() {
        var planner = PlaceActionPlanner(category: .cafe, website: "cafe.com",
                                         owner: .init(menu: "cafe.com/menu"), hasInAppMenu: true, takesOrders: true)
        #expect(planner.actions().first?.kind == .inAppMenu(ordering: true))
        planner.hasInAppMenu = false
        #expect(planner.actions().first?.kind == .link("https://cafe.com/menu"))
        planner.owner = nil
        planner.publishedMenuLink = "https://cafe.com/pdf"
        #expect(planner.actions().first?.kind == .link("https://cafe.com/pdf"))
        planner.publishedMenuLink = nil
        #expect(planner.actions().first?.kind == .link("https://cafe.com"))
    }

    @Test func noMenuForAShopUnlessTheStoreAddsOne() {
        var planner = PlaceActionPlanner(category: .retail, website: "shop.com")
        #expect(titles(planner).isEmpty)
        planner.owner = .init(menu: "shop.com/catalog")
        #expect(titles(planner) == ["Menu"])
    }

    @Test func ownerChoicesComeFirstAndReplaceOrHideTheAutomaticOnes() {
        let owner = PlaceActionPlanner.OwnerButtons(reserve: "resy.com/stir", order: "toasttab.com/stir", hidden: ["delivery"])
        let planner = PlaceActionPlanner(category: .restaurant, reservable: true, website: "stir.com",
                                         distanceMeters: 20_000, owner: owner, partnerGroups: Self.catalog)
        // Their Reserve link replaces OpenTable; Delivery is off; the row is full before Ride
        #expect(titles(planner) == ["Menu", "Reserve", "Order"])
        #expect(planner.actions()[1].kind == .link("https://resy.com/stir"))
    }

    @Test func everyOwnerLinkShowsEvenPastThree() {
        let owner = PlaceActionPlanner.OwnerButtons(reserve: "a.com", order: "b.com", catering: "c.com", book: "d.com")
        let planner = PlaceActionPlanner(category: .restaurant, website: "e.com", owner: owner, partnerGroups: Self.catalog)
        #expect(titles(planner) == ["Menu", "Reserve", "Order", "Catering", "Book"])
    }

    @Test func homeAndWorkGetNothing() {
        #expect(PlaceActionPlanner(category: .home, website: "x.com", partnerGroups: Self.catalog).actions().isEmpty)
    }

    @Test func webAddresses() {
        #expect(PlaceActionPlanner.webAddress(" ilios.com/menu ") == "https://ilios.com/menu")
        #expect(PlaceActionPlanner.webAddress("tel:704") == nil)
        #expect(PlaceActionPlanner.webAddress("") == nil)
    }
}
