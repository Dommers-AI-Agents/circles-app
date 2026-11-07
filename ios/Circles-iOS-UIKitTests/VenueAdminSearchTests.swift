import Testing
@testable import Circles_iOS

struct VenueAdminSearchTests {
    let store: [String?] = ["Wooden Robot Coffee Bar", "1440 S Tryon St, Charlotte", nil, "owner@woodenrobot.com", "W8ZL", "R8ZL"]

    @Test(arguments: ["", "  ", "wooden", "WOODEN", "coffee wooden", "tryon", "woodenrobot.com", "r8zl"])
    func finds(_ query: String) {
        #expect(VenueAdminSearch.matches(query, fields: store))
    }

    @Test(arguments: ["pizza", "wooden pizza", "belmar"])
    func misses(_ query: String) {
        #expect(!VenueAdminSearch.matches(query, fields: store))
    }

    @Test func accents() {
        #expect(VenueAdminSearch.matches("cafe", fields: ["Café Monte"]))
        #expect(VenueAdminSearch.matches("café", fields: ["Cafe Monte"]))
    }
}
