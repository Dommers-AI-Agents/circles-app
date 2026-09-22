import Foundation
import Testing
@testable import Circles_iOS

/// The rating tap's Google link — the venue name must survive as one query.
struct GoogleReviewsLinkTests {
    private func queryItems(_ url: URL?) -> [URLQueryItem] {
        guard let url else { return [] }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    @Test func ampersandStaysInsideTheQuery() {
        let url = GoogleReviewsLink.url(name: "Pasta & Provisions", address: "1528 Providence Rd")
        let items = queryItems(url)
        #expect(items.count == 1)
        #expect(items.first?.name == "q")
        #expect(items.first?.value == "Pasta & Provisions 1528 Providence Rd reviews")
        #expect(url?.absoluteString.contains("%26") == true)
    }

    @Test func otherDelimitersAreEncodedToo() {
        let url = GoogleReviewsLink.url(name: "Fish+Chips #1 = best?", address: nil)
        #expect(queryItems(url).first?.value == "Fish+Chips #1 = best? reviews")
        let encoded = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery }
        #expect(encoded == "q=Fish%2BChips%20%231%20%3D%20best%3F%20reviews")
    }

    @Test func addressIsOptional() {
        #expect(queryItems(GoogleReviewsLink.url(name: "Cafe", address: nil)).first?.value == "Cafe reviews")
        #expect(queryItems(GoogleReviewsLink.url(name: "Cafe", address: "  ")).first?.value == "Cafe reviews")
    }

    @Test func hostAndPath() {
        let url = GoogleReviewsLink.url(name: "Cafe", address: nil)
        #expect(url?.host == "www.google.com")
        #expect(url?.path == "/search")
    }
}

struct URLQueryValueEncodingTests {
    @Test func delimitersAreEncoded() {
        #expect("a&b=c+d?e#f".urlQueryValueEncoded == "a%26b%3Dc%2Bd%3Fe%23f")
        #expect("plain words".urlQueryValueEncoded == "plain%20words")
    }
}
