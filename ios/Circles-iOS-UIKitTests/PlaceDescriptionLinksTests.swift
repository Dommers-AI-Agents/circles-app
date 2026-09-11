import Testing
import Foundation
@testable import Circles_iOS

/// "Website: https://…" lines in a place description become tappable links.
struct PlaceDescriptionLinksTests {
    @Test func findsTheUrlAfterTheWebsitePrefix() {
        let text = "Great coffee.\nWebsite: https://amelies.example/menu\nOpen late."
        let links = PlaceDescriptionLinks.websiteLinks(in: text)
        #expect(links.count == 1)
        #expect(links.first?.url == URL(string: "https://amelies.example/menu"))
        let range = links.first!.range
        #expect((text as NSString).substring(with: range) == "https://amelies.example/menu")
    }

    @Test func ignoresBareUrlsAndNonHttpSchemes() {
        #expect(PlaceDescriptionLinks.websiteLinks(in: "Visit https://x.example today").isEmpty)
        #expect(PlaceDescriptionLinks.websiteLinks(in: "Website: ftp://x.example").isEmpty)
        #expect(PlaceDescriptionLinks.websiteLinks(in: "No links here").isEmpty)
    }

    @Test func findsEveryWebsiteLine() {
        let text = "Website: http://a.example\nPhone: 1\nWebsite: https://b.example/x"
        #expect(PlaceDescriptionLinks.websiteLinks(in: text).map { $0.url.absoluteString } == ["http://a.example", "https://b.example/x"])
    }
}
