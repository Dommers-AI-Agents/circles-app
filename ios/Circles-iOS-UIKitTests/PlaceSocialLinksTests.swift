import Testing
import UIKit
@testable import Circles_iOS

/// A store's Instagram / Facebook / X links on its place page (Wes,
/// 2026-11-24): a button per link that is set, nothing when none are.
@MainActor
struct PlaceSocialLinksTests {

    @Test func onlyTheLinksThatAreSetGetAButton() {
        let links = PlaceSocialLinks(instagram: "https://www.instagram.com/giddygoat", facebook: nil, twitter: "https://x.com/giddygoat")
        #expect(links.buttons.map(\.network) == [.instagram, .twitter])
        #expect(links.buttons.map(\.url.absoluteString) == ["https://www.instagram.com/giddygoat", "https://x.com/giddygoat"])
        #expect(!links.isEmpty)
    }

    @Test func noLinksMeansNoButtons() {
        #expect(PlaceSocialLinks().isEmpty)
        #expect(PlaceSocialLinks(instagram: "", facebook: "  ", twitter: nil).isEmpty)
    }

    @Test func aLinkThatLeavesItsNetworkIsNeverOpened() {
        #expect(PlaceSocialLinks.safeURL("https://evil.example/giddygoat", for: .instagram) == nil)
        #expect(PlaceSocialLinks.safeURL("https://instagram.com.evil.example/x", for: .instagram) == nil)
        #expect(PlaceSocialLinks.safeURL("http://instagram.com/giddygoat", for: .instagram) == nil)
        #expect(PlaceSocialLinks.safeURL("javascript:alert(1)", for: .twitter) == nil)
        #expect(PlaceSocialLinks.safeURL("https://instagram.com/giddygoat", for: .facebook) == nil)
        #expect(PlaceSocialLinks.safeURL("https://m.facebook.com/GiddyGoat", for: .facebook) != nil)
        #expect(PlaceSocialLinks.safeURL("https://twitter.com/giddygoat", for: .twitter) != nil)
    }

    @Test func storeDetailsShowTheHandle() {
        #expect(PlaceSocialLinks.display("https://www.instagram.com/giddygoat", for: .instagram) == "@giddygoat")
        #expect(PlaceSocialLinks.display("https://x.com/giddygoat", for: .twitter) == "@giddygoat")
        #expect(PlaceSocialLinks.display("https://www.facebook.com/profile.php?id=100064", for: .facebook) == "www.facebook.com/profile.php?id=100064")
        #expect(PlaceSocialLinks.display(nil, for: .instagram) == nil)
    }

    @Test func thePlaceReadsItsLinksFromTheServer() throws {
        let json = #"{"instagram":"https://www.instagram.com/giddygoat","facebook":null}"#
        let links = try JSONDecoder().decode(PlaceSocialLinks.self, from: Data(json.utf8))
        #expect(links == PlaceSocialLinks(instagram: "https://www.instagram.com/giddygoat", facebook: nil, twitter: nil))
    }

    @Test func theRowHasAButtonPerLinkAndNoneWithoutLinks() {
        let row = PlaceSocialLinksRowView()
        row.configure(nil)
        #expect(row.buttonCount == 0)
        row.configure(PlaceSocialLinks(instagram: "https://www.instagram.com/a", facebook: "https://www.facebook.com/a", twitter: nil))
        #expect(row.buttonCount == 2)
        var opened: [URL] = []
        row.onOpen = { opened.append($0) }
        (row.arrangedSubviews[1] as? UIButton)?.sendActions(for: .touchUpInside)
        #expect(opened.map(\.absoluteString) == ["https://www.facebook.com/a"])
        // The store removed its links: the buttons go
        row.configure(PlaceSocialLinks())
        #expect(row.buttonCount == 0)
    }

    @Test func everyNetworkHasAMark() {
        for network in PlaceSocialLinks.Network.allCases {
            let mark = SocialGlyph.image(for: network)
            #expect(mark.size == CGSize(width: 17, height: 17))
            #expect(mark.renderingMode == .alwaysTemplate)
        }
    }
}
