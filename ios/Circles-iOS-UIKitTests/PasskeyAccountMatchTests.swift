import Testing
@testable import Circles_iOS

/// A passkey is named for, and offered to, the account it belongs to.
struct PasskeyAccountMatchTests {

    @Test func serverNameWinsOverTheAppsGuess() {
        #expect(PasskeyAccountMatch.label(serverName: "sgroiwes@gmail.com", fallback: "tester149@example.com") == "sgroiwes@gmail.com")
        #expect(PasskeyAccountMatch.label(serverName: nil, fallback: "me@example.com") == "me@example.com")
        #expect(PasskeyAccountMatch.label(serverName: "  ", fallback: "me@example.com") == "me@example.com")
    }

    @Test func offerOnlyForTheSignedInAccount() {
        #expect(PasskeyAccountMatch.isForSignedInAccount(stashedEmail: "Me@Example.com ", signedInEmail: "me@example.com"))
        #expect(!PasskeyAccountMatch.isForSignedInAccount(stashedEmail: "tester149@example.com", signedInEmail: "sgroiwes@gmail.com"))
        #expect(!PasskeyAccountMatch.isForSignedInAccount(stashedEmail: "me@example.com", signedInEmail: nil))
        #expect(!PasskeyAccountMatch.isForSignedInAccount(stashedEmail: nil, signedInEmail: "me@example.com"))
        #expect(!PasskeyAccountMatch.isForSignedInAccount(stashedEmail: "", signedInEmail: ""))
    }
}
