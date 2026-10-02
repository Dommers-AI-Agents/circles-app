import Testing
@testable import Circles_iOS

/// A launch-snapshot refresh never replaces cached data with nothing.
struct LaunchSnapshotMergeTests {
    @Test func aPartThatDidNotArriveKeepsTheOldValue() {
        #expect(LaunchSnapshotMerge.choose(.connections, fresh: [Int](), previous: [1, 2, 3], arrived: []) == [1, 2, 3])
        #expect(LaunchSnapshotMerge.choose(.activities, fresh: [Int](), previous: [7], arrived: [.connections]) == [7])
    }

    @Test func aPartThatArrivedWinsEvenWhenEmpty() {
        #expect(LaunchSnapshotMerge.choose(.moments, fresh: [9], previous: [1], arrived: [.moments]) == [9])
        // Really has no connections now (e.g. removed them all): kept empty
        #expect(LaunchSnapshotMerge.choose(.connections, fresh: [Int](), previous: [1], arrived: [.connections]) == [])
    }

    @Test func noPreviousSnapshotMeansFresh() {
        let fresh = PreloadedData(user: nil, circles: [], networkCircles: [], allPlaces: [], connections: [],
                                  unreadMessageCount: 2, pendingConnectionCount: 1, activities: [], moments: [])
        let merged = LaunchSnapshotMerge.merge(fresh: fresh, arrived: [], previous: nil)
        #expect(merged.unreadMessageCount == 2 && merged.pendingConnectionCount == 1)
    }
}
