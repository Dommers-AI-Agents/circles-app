import Testing
@testable import Circles_iOS

struct MomentsRefreshPlanTests {
    @Test func samePageIsUnchanged() {
        #expect(MomentsRefreshPlan.plan(current: ["a", "b", "c"], fresh: ["a", "b", "c"]) == .unchanged)
    }

    @Test func morePagesLoadedThanTheFreshPageIsUnchanged() {
        #expect(MomentsRefreshPlan.plan(current: ["a", "b", "c", "d"], fresh: ["a", "b"]) == .unchanged)
    }

    @Test func newMomentsAtTheTopAreOffered() {
        #expect(MomentsRefreshPlan.plan(current: ["a", "b"], fresh: ["x", "y", "a"]) == .newMoments(count: 2))
    }

    @Test func aDeletedMomentIsNotNews() {
        #expect(MomentsRefreshPlan.plan(current: ["a", "b", "c"], fresh: ["a", "c"]) == .unchanged)
    }
}
