import Testing
import Foundation
@testable import Circles_iOS

/// The login screen's "Welcome back" (2026-11-01).
struct LastSignInHintTests {
    @Test func readsTheRememberedAccount() throws {
        let hint = try #require(LastSignInHint(stored: ["id": "u1", "email": "brit@gmail.com", "displayName": "Brittany R",
                                                        "photo": "https://x/p.jpg", "method": "google"]))
        #expect(hint.method == .google && hint.firstName == "Brittany")
        #expect(hint.lastTimeLine == "Last time you used Google · brit@gmail.com")
        #expect(LastSignInHint(stored: nil) == nil)
        #expect(LastSignInHint(stored: ["email": "x@y.z"]) == nil)   // no account id
    }

    @Test func methodsAndHiddenEmails() throws {
        #expect(LastSignInHint.method("email") == .password && LastSignInHint.method("firebase") == .password)
        #expect(LastSignInHint.method("passkey") == .passkey && LastSignInHint.method(nil) == .other)
        let apple = try #require(LastSignInHint(stored: ["id": "u2", "email": "abc@privaterelay.appleid.com", "method": "apple"]))
        #expect(apple.isHiddenEmail && apple.lastTimeLine == "Last time you used Apple · (hidden email)")
        let face = try #require(LastSignInHint(stored: ["id": "u3", "email": "pat@x.com", "method": "passkey"]))
        #expect(face.lastTimeLine == "Last time you used Face ID · pat@x.com")
    }
}
