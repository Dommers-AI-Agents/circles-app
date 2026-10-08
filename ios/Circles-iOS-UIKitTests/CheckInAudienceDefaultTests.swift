import Testing
@testable import Circles_iOS

struct CheckInAudienceDefaultTests {
    @Test func roundTripsEveryChoice() {
        for choice in [CheckInAudienceChoice.justMe, .connections, .everyone, .list("abc123")] {
            #expect(CheckInAudienceChoice(storedValue: choice.storedValue) == choice)
        }
        #expect(CheckInAudienceChoice(storedValue: "list:") == nil)
        #expect(CheckInAudienceChoice(storedValue: "bogus") == nil)
        #expect(CheckInAudienceChoice(storedValue: nil) == nil)
    }

    @Test func opensOnTheDefaultUnlessItsListIsGone() {
        #expect(CheckInAudienceChoice.initial(saved: nil, listIds: []) == .connections)
        #expect(CheckInAudienceChoice.initial(saved: "list:ic1", listIds: ["ic1"]) == .list("ic1"))
        #expect(CheckInAudienceChoice.initial(saved: "list:ic1", listIds: ["other"]) == .connections)
        #expect(CheckInAudienceChoice.initial(saved: "list:ic1", listIds: nil) == .list("ic1"))
        #expect(CheckInAudienceChoice.initial(saved: "justMe", listIds: []) == .justMe)
    }
}
