import Testing
@testable import Circles_iOS

struct SavedPlaceMatcherTests {
    private struct P { let id: String; let venue: String; let name: String; let address: String }
    private let places = [
        P(id: "1", venue: "a", name: "Sgroi Innovations - KnightATV", address: "3212 Shafto Rd, Tinton Falls, NJ"),
        P(id: "2", venue: "a", name: "Sgroi Innovations - KnightATV", address: "3212 Shafto Rd, Tinton Falls, NJ"),
        P(id: "3", venue: "b", name: "Night Swim", address: "1 Knight St, Charlotte"),
        P(id: "4", venue: "c", name: "Café Crêpe", address: "South End, Charlotte"),
    ]
    private func find(_ q: String) -> [String] {
        SavedPlaceMatcher.matches(q, in: places, name: \.name, address: \.address, key: \.venue).map(\.id)
    }

    @Test func findsAFarAwaySaveByAnyWordOfItsName() {
        #expect(find("knight") == ["1", "3"])          // name match first, then address
        #expect(find("KnightATV") == ["1"])
        #expect(find("knight atv") == ["1"])           // spaces ignored
        #expect(find("sgroi") == ["1"])                // the same venue saved twice shows once
    }

    @Test func accentsAndCaseDoNotMatter() {
        #expect(find("cafe crepe") == ["4"])
        #expect(find("CAFÉ") == ["4"])
    }

    @Test func needsEveryWordAndSomethingToMatch() {
        #expect(find("knight pizza").isEmpty)
        #expect(find("  ").isEmpty)
        #expect(find("zz").isEmpty)
    }
}
