import Testing
@testable import Circles_iOS

struct GenericJoinCodeTests {
    @Test func onlyTheJoinCodeMatches() {
        #expect(GenericJoinCode.matches("JOINUS"))
        #expect(GenericJoinCode.matches("joinus"))
        #expect(GenericJoinCode.matches(" JoinUs\n"))
        #expect(!GenericJoinCode.matches("WIN123"))
        #expect(!GenericJoinCode.matches("JOINUS2"))
    }
}
