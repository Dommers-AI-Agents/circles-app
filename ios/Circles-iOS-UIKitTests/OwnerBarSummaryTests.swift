import Testing
@testable import Circles_iOS

/// The owner bar on the owner's own store card leads with what needs them.
struct OwnerBarSummaryTests {
    typealias S = OwnerBarSummary

    @Test func newOrdersComeFirstWhileOrderingIsOn() {
        #expect(S.headline(.init(orderingEnabled: true, newOrders: 2)) == "2 new orders")
        #expect(S.headline(.init(orderingEnabled: true, newOrders: 1)) == "1 new order")
        #expect(S.headline(.init(orderingEnabled: true, newOrders: 0)) == "No new orders")
        #expect(S.needsAttention(.init(orderingEnabled: true, newOrders: 1)))
        #expect(!S.needsAttention(.init(orderingEnabled: true, newOrders: 0)))
    }

    @Test func withoutOrderingTheNumbersLead() {
        #expect(S.headline(.init(orderingEnabled: false, newOrders: 3, saves: 14, visits: 3)) == "14 saves \u{00B7} 3 visits")
        #expect(!S.needsAttention(.init(orderingEnabled: false, newOrders: 3)))
    }

    @Test func detailCountsAndFreePlan() {
        #expect(S.detail(.init(orderingEnabled: true, saves: 14, visits: 3)) == "14 saves \u{00B7} 3 visits")
        #expect(S.detail(.init(orderingEnabled: true, saves: 1, visits: 1, premium: false)) == "1 save \u{00B7} 1 visit \u{00B7} Free plan")
        #expect(S.detail(.init(premium: false)) == "Free plan")
        #expect(S.detail(.init()) == "Stats & insights")
    }
}
