import Testing
@testable import Circles_iOS

/// A place fetch that failed and brought back nothing must not wipe the
/// pins already on screen.
struct PlaceRefreshMergeTests {
    @Test func aCompleteFetchAlwaysReplaces() {
        #expect(PlaceRefreshMerge.shouldReplaceInMemory(fetched: 12, fetchComplete: true, current: 40))
        #expect(PlaceRefreshMerge.shouldReplaceInMemory(fetched: 0, fetchComplete: true, current: 40))
    }

    @Test func offlineFetchKeepsTheCachedPins() {
        #expect(!PlaceRefreshMerge.shouldReplaceInMemory(fetched: 0, fetchComplete: false, current: 40))
    }

    @Test func aPartialFetchWithSomethingStillPaints() {
        #expect(PlaceRefreshMerge.shouldReplaceInMemory(fetched: 5, fetchComplete: false, current: 40))
    }

    @Test func nothingToProtectMeansReplace() {
        #expect(PlaceRefreshMerge.shouldReplaceInMemory(fetched: 0, fetchComplete: false, current: 0))
    }
}
