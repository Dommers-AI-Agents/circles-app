import Testing
@testable import Circles_iOS

/// What adding several photos to a place says while it runs and when it ends.
struct PlacePhotoBatchSummaryTests {

    @Test func progressNamesThePhotoInABatch() {
        #expect(PlacePhotoBatchSummary.progress(current: 1, total: 1) == "Uploading photo…")
        #expect(PlacePhotoBatchSummary.progress(current: 2, total: 3) == "Uploading 2 of 3…")
    }

    @Test func allAdded() {
        #expect(PlacePhotoBatchSummary.result(added: 1, failed: 0)?.message == "Photo added")
        #expect(PlacePhotoBatchSummary.result(added: 3, failed: 0)?.message == "3 photos added")
    }

    @Test func photosWithoutSignalAreSavedForLater() {
        let summary = PlacePhotoBatchSummary.result(added: 2, failed: 1)
        #expect(summary?.title == "Almost there")
        #expect(summary?.message == "2 added. 1 more will be added when you're back online.")
    }

    @Test func allWaitingForSignal() {
        #expect(PlacePhotoBatchSummary.result(added: 0, failed: 1)?.message == "No signal right now. Your photo will be added when you're back online.")
        #expect(PlacePhotoBatchSummary.result(added: 0, failed: 4)?.message == "No signal right now. Your 4 photos will be added when you're back online.")
    }

    @Test func nothingAttemptedSaysNothing() {
        #expect(PlacePhotoBatchSummary.result(added: 0, failed: 0) == nil)
    }
}
