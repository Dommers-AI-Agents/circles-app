import Testing
import CoreLocation
@testable import Circles_iOS

/// Saving Edit Place sends only the shared details that changed.
struct PlaceEditPlanTests {
    private let original = PlaceEditPlan.Details(
        name: "Leroy Fox - South End", address: "1824 S Tryon St, Charlotte, NC 28203, USA",
        category: "restaurant", description: "Fried chicken.", phone: "704-555-0100",
        website: "https://leroyfox.com", coordinate: CLLocationCoordinate2D(latitude: 35.2, longitude: -80.86))

    @Test func nothingChangedSendsNothing() {
        var edited = original
        edited.name = "  Leroy Fox - South End "
        edited.coordinate = CLLocationCoordinate2D(latitude: 35.200001, longitude: -80.860001)
        #expect(PlaceEditPlan.detailChanges(original: original, edited: edited).isEmpty)
    }

    @Test func onlyChangedFieldsAreSent() {
        var edited = original
        edited.phone = "704-555-0199"
        edited.category = "bar"
        let body = PlaceEditPlan.detailChanges(original: original, edited: edited)
        #expect(Set(body.keys) == ["phone", "category"])
        #expect(body["phone"] as? String == "704-555-0199")
    }

    @Test func clearingAFieldSendsEmpty() {
        var edited = original
        edited.website = "   "
        #expect(PlaceEditPlan.detailChanges(original: original, edited: edited)["website"] as? String == "")
    }

    @Test func aNameIsNeverCleared() {
        var edited = original
        edited.name = ""
        #expect(PlaceEditPlan.detailChanges(original: original, edited: edited)["name"] == nil)
    }

    @Test func aMovedPinSendsALocation() {
        var edited = original
        edited.coordinate = CLLocationCoordinate2D(latitude: 35.21, longitude: -80.85)
        let location = PlaceEditPlan.detailChanges(original: original, edited: edited)["location"] as? [String: Any]
        #expect(location?["type"] as? String == "Point")
        #expect(location?["coordinates"] as? [Double] == [-80.85, 35.21])
    }
}
