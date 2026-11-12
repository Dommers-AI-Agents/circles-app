import Testing
@testable import Circles_iOS

/// The scan bubble says what the scan is for (Wes, 2026-11-12)
struct ScanLoadingCopyTests {
    @Test func aWindowStickerSetsYouUpToSaveTheStore() {
        #expect(ScanLoadingCopy.message(kind: "window", name: "Pasta & Provisions") == "Setting you up to save Pasta & Provisions…")
        #expect(ScanLoadingCopy.message(kind: "window", name: nil) == "Setting you up to save this place…")
    }

    @Test func theJoinCodeSetsYouUpToJoin() {
        #expect(ScanLoadingCopy.message(kind: "generic", name: nil) == "Setting you up to join…")
        #expect(ScanLoadingCopy.message(kind: "generic", name: "FavCircles") == "Setting you up to join…")
    }

    @Test func onlyARegisterCardTalksAboutRewards() {
        #expect(ScanLoadingCopy.message(kind: "register", name: "Pasta & Provisions") == "Checking rewards at Pasta & Provisions…")
        #expect(ScanLoadingCopy.message(kind: "register", name: " ") == "Checking rewards…")
    }

    @Test func beforeTheLookupAnswersNothingIsPromised() {
        #expect(ScanLoadingCopy.initial == "Setting you up…")
        #expect(ScanLoadingCopy.message(kind: nil, name: nil) == ScanLoadingCopy.initial)
        #expect(ScanLoadingCopy.message(kind: nil, name: "Pasta & Provisions") == "Setting you up at Pasta & Provisions…")
    }
}
