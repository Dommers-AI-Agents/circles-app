import Testing
@testable import Circles_iOS

/// "Is this me?" never says yes to nothing.
struct AuthIsMeTests {
    @Test func missingIdsAreNeverMe() {
        #expect(!AuthService.shared.isMe(nil))
        #expect(!AuthService.shared.isMe(""))
    }
}
