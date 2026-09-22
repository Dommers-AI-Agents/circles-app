import Testing
@testable import Circles_iOS

/// Coming back to the app while Sleep Sounds is playing lands on the sound —
/// unless doing so would dismiss something or re-open the page already showing.
struct NowPlayingReturnGateTests {
    private func playing(signedIn: Bool = true, modal: Bool = false, showing: Bool = false) -> NowPlayingReturnGate.Context {
        .init(isPlaying: true, isSignedIn: signedIn, hasModal: modal, isShowingSleepSounds: showing)
    }

    @Test func returningWhileTheSoundPlaysOpensIt() {
        #expect(NowPlayingReturnGate.shouldOpenSleepSounds(playing()))
    }

    @Test func nothingPlayingMeansNothingChanges() {
        var c = playing(); c.isPlaying = false
        #expect(!NowPlayingReturnGate.shouldOpenSleepSounds(c))
    }

    /// The navigation pops to root and dismisses whatever is presented. Over
    /// an Apple Pay sheet or the postcard composer that is destructive, so a
    /// modal always wins over the sound.
    @Test func neverOverAModal() {
        #expect(!NowPlayingReturnGate.shouldOpenSleepSounds(playing(modal: true)))
    }

    @Test func notWhenItIsAlreadyTheScreen() {
        #expect(!NowPlayingReturnGate.shouldOpenSleepSounds(playing(showing: true)))
    }

    @Test func notWhenSignedOut() {
        #expect(!NowPlayingReturnGate.shouldOpenSleepSounds(playing(signedIn: false)))
    }
}
