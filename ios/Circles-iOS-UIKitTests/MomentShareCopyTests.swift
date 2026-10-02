import Testing
@testable import Circles_iOS

struct MomentShareCopyTests {
    @Test func titleNamesThePlace() {
        #expect(MomentShareCopy.title(placeName: "Bank of America Stadium") == "Moment on FavCircles: Bank of America Stadium")
        #expect(MomentShareCopy.title(placeName: "  Pier 39 ") == "Moment on FavCircles: Pier 39")
    }

    @Test func noPlaceMeansNoColon() {
        #expect(MomentShareCopy.title(placeName: nil) == "Moment on FavCircles")
        #expect(MomentShareCopy.title(placeName: "   ") == "Moment on FavCircles")
    }
}
