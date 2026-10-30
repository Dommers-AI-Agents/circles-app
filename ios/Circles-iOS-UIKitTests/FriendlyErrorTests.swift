import Testing
import Foundation
@testable import Circles_iOS

/// Every alert's words (2026-10-30): plain, never system text.
struct FriendlyErrorTests {

    @Test func connectionProblemsSaySo() {
        #expect(FriendlyError.message(for: APIError.noInternet) == FriendlyError.offline)
        #expect(FriendlyError.message(for: URLError(.timedOut)) == FriendlyError.offline)
        #expect(FriendlyError.clean("The request timed out.") == FriendlyError.offline)
    }

    @Test func serverFailuresAndTechnicalTextBecomeTheFriendlyLine() {
        let body = Data(#"{"success":false,"error":"Failed to process scan"}"#.utf8)
        #expect(FriendlyError.message(for: APIError.httpError(500, body)) == FriendlyError.generic)
        #expect(FriendlyError.message(for: APIError.decodingFailed(URLError(.cannotParseResponse))) == FriendlyError.generic)
        #expect(FriendlyError.message(for: APIError.unknown) == FriendlyError.generic)
        #expect(FriendlyError.clean("The operation couldn’t be completed. (kCLErrorDomain error 1.)") == FriendlyError.generic)
        #expect(FriendlyError.clean("Failed to update circle: Server error occurred") == FriendlyError.generic)
    }

    @Test func messagesWrittenForPeopleAreKept() {
        let body = Data(#"{"success":false,"code":"ordering_off","message":"This store isn’t taking orders right now."}"#.utf8)
        #expect(FriendlyError.message(for: APIError.httpError(409, body)) == "This store isn’t taking orders right now.")
        #expect(FriendlyError.clean("Pick a circle first") == "Pick a circle first")
        #expect(FriendlyError.message(for: APIError.unauthorized) == FriendlyError.signIn)
    }
}
