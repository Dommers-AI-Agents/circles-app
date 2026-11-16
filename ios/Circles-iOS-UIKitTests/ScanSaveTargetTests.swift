import Testing
@testable import Circles_iOS

/// Where a scanned place goes without asking (2026-11-16): the App Clip's rule.
struct ScanSaveTargetTests {
    private struct Stub: SystemCircleFlagged, Equatable {
        let name: String
        var systemKind: String? = nil
        var isDefaultCircle: Bool? = nil
    }

    private let wantToTry = Stub(name: "Want to Try", systemKind: "wantToTry")
    private let favorites = Stub(name: "Favorite Local Spots", systemKind: "favoriteLocal")
    private let brunch = Stub(name: "Brunch")

    @Test func aPlaceSomeoneShowedYouGoesToWantToTry() {
        #expect(ScanSaveTarget.pick(.placeQR, from: [brunch, favorites, wantToTry]) == wantToTry)
        #expect(ScanSaveTarget.pick(.placeQR, from: [brunch, favorites]) == favorites)
        #expect(ScanSaveTarget.pick(.placeQR, from: [brunch]) == brunch)
        #expect(ScanSaveTarget.pick(.placeQR, from: [Stub]()) == nil)
    }

    @Test func aStoreYouAreAtGoesToFavoriteLocalSpots() {
        #expect(ScanSaveTarget.pick(.storeSticker, from: [brunch, wantToTry, favorites]) == favorites)
        #expect(ScanSaveTarget.pick(.storeSticker, from: [brunch, wantToTry]) == wantToTry)
        #expect(ScanSaveTarget.pick(.storeSticker, from: [brunch]) == brunch)
    }

    @Test func aRenamedStarterStillCountsByItsFlag() {
        let renamed = Stub(name: "Places to try", systemKind: "wantToTry")
        #expect(ScanSaveTarget.pick(.placeQR, from: [brunch, renamed]) == renamed)
        // A legacy, unflagged starter counts by its name
        let legacy = Stub(name: "Favorite Local Spots")
        #expect(ScanSaveTarget.pick(.storeSticker, from: [brunch, legacy]) == legacy)
    }
}
