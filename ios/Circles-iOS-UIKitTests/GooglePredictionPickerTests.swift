import Testing
@testable import Circles_iOS

/// "Uptown Yolk Cafe" was saved as "116 W Catherine St" (2026-10-23): the
/// Google lookup fell back to the address Google offered first.
@Suite struct GooglePredictionPickerTests {
    typealias C = GooglePredictionPicker.Candidate
    let address = C(name: "116 W Catherine St", types: ["premise", "geocode"])
    let yolk = C(name: "Uptown Yolk", types: ["restaurant", "food", "point_of_interest", "establishment"])

    @Test func theBusinessIsChosenOverTheAddressGoogleOffersFirst() {
        #expect(GooglePredictionPicker.pick(name: "Uptown Yolk Cafe", from: [address, yolk]) == 1)
    }

    @Test func onlyAnAddressMeansNoGoogleMatch() {
        #expect(GooglePredictionPicker.pick(name: "Uptown Yolk Cafe", from: [address]) == nil)
    }

    @Test func aDifferentBusinessIsNeverTaken() {
        let parking = C(name: "Vantage South End - Parking", types: ["parking", "establishment"])
        #expect(GooglePredictionPicker.pick(name: "Uptown Yolk Cafe", from: [parking]) == nil)
    }

    @Test func anExactNameWinsOverAPartialOne() {
        let shop = C(name: "Starbucks Reserve", types: ["cafe", "establishment"])
        let exact = C(name: "Starbucks", types: ["cafe", "establishment"])
        #expect(GooglePredictionPicker.pick(name: "Starbucks", from: [shop, exact]) == 1)
    }

    @Test func punctuationAndAmpersandsDontMatter() {
        let joes = C(name: "Joes Pizza and Pasta", types: ["restaurant", "establishment"])
        #expect(GooglePredictionPicker.pick(name: "Joe’s Pizza & Pasta", from: [joes]) == 0)
    }

    @Test func addressOnlyTypes() {
        #expect(GooglePredictionPicker.isAddressOnly(["street_address"]))
        #expect(!GooglePredictionPicker.isAddressOnly(["premise", "establishment"]))
        #expect(!GooglePredictionPicker.isAddressOnly([]))
    }
}
