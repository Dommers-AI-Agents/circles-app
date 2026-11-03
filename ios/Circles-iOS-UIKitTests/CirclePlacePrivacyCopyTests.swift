import Testing
@testable import Circles_iOS

struct CirclePlacePrivacyCopyTests {
    @Test func oneAndMany() {
        #expect(CirclePlacePrivacyCopy.title(count: 1, tierTitle: "Public") == "Make the 1 place Public too?")
        #expect(CirclePlacePrivacyCopy.title(count: 6, tierTitle: "Private") == "Make all 6 places Private too?")
        #expect(CirclePlacePrivacyCopy.message(count: 1).hasPrefix("1 place in this circle has its own privacy"))
        #expect(CirclePlacePrivacyCopy.message(count: 6).hasPrefix("6 places in this circle have their own privacy"))
        #expect(CirclePlacePrivacyCopy.confirm(tierTitle: "Connections") == "Make them Connections")
    }
}
