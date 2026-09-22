import Testing
@testable import Circles_iOS

struct WidgetSnapshotPolicyTests {
    @Test func offlineRefreshKeepsTheLastSnapshot() {
        #expect(!WidgetSnapshotPolicy.shouldReplace(activitiesSucceeded: false, coinsSucceeded: false))
    }

    @Test func anySuccessfulFetchWritesANewOne() {
        #expect(WidgetSnapshotPolicy.shouldReplace(activitiesSucceeded: true, coinsSucceeded: false))
        #expect(WidgetSnapshotPolicy.shouldReplace(activitiesSucceeded: false, coinsSucceeded: true))
        #expect(WidgetSnapshotPolicy.shouldReplace(activitiesSucceeded: true, coinsSucceeded: true))
    }
}
