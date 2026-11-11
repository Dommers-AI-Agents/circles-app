import Testing
import MapKit
@testable import Circles_iOS

/// An Apple Maps pick vouches for itself only when the saved place is that pick.
struct ApplePlaceIdentityTests {
    private func item(named name: String?) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 33.3, longitude: -111.8)))
        item.name = name
        return item
    }

    @Test func sameNameVouches() {
        #expect(ApplePlaceIdentity.vouches(mapItem: item(named: "Over Easy"), savedName: "Over Easy"))
        #expect(ApplePlaceIdentity.vouches(mapItem: item(named: "Over Easy"), savedName: "over  easy"))
        #expect(ApplePlaceIdentity.vouches(mapItem: item(named: "Joe's Café"), savedName: "Joes Cafe") == false) // é ≠ e: still that café? no — spelled differently, user's call
    }

    @Test func renamedOrUnnamedDoesNot() {
        #expect(ApplePlaceIdentity.vouches(mapItem: item(named: "Over Easy"), savedName: "Dad's breakfast spot") == false)
        #expect(ApplePlaceIdentity.vouches(mapItem: item(named: nil), savedName: "116 W Catherine St") == false)
        #expect(ApplePlaceIdentity.vouches(mapItem: item(named: ""), savedName: "") == false)
        #expect(ApplePlaceIdentity.vouches(mapItem: nil, savedName: "Over Easy") == false)
    }

    @Test func identifierIsNilWithoutAMapItem() {
        #expect(ApplePlaceIdentity.identifier(of: nil) == nil)
        #expect(ApplePlaceIdentity.identifier(of: item(named: "Over Easy")) == nil) // a hand-made item has no Apple id
    }
}
