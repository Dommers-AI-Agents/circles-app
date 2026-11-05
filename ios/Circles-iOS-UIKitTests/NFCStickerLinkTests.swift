import Foundation
import Testing
@testable import Circles_iOS

/// Manage Store → NFC stickers: what a checked sticker is, and its taps line
struct NFCStickerLinkTests {

    private let window = "https://api.favcircles.com/s/WIN123"

    private func match(_ link: String, tags: Set<String> = ["table-7"]) -> NFCStickerMatch {
        NFCStickerLink.match(link, windowUrl: window, knownTags: tags)
    }

    @Test func recognisesThisStoresStickers() {
        #expect(match("https://api.favcircles.com/s/WIN123?t=table-7") == .sticker(tag: "table-7"))
        #expect(match("https://api.favcircles.com/s/win123?t=table-7") == .sticker(tag: "table-7"))
        #expect(match("https://api.favcircles.com/s/WIN123?t=patio") == .removedTag("patio"))
        #expect(match("https://api.favcircles.com/s/WIN123") == .windowLink)
    }

    /// Register stickers carry the register link (2026-11-05)
    @Test func recognisesRegisterStickers() {
        let register = "https://api.favcircles.com/s/REG456"
        #expect(NFCStickerLink.match("https://api.favcircles.com/s/REG456?t=counter", windowUrl: window, registerUrl: register,
                                     knownTags: ["counter"]) == .sticker(tag: "counter"))
        // Without the register link, it isn't recognised as this store's
        #expect(NFCStickerLink.match("https://api.favcircles.com/s/REG456?t=counter", windowUrl: window,
                                     knownTags: ["counter"]) == .otherStore)
    }

    @Test func otherLinks() {
        #expect(match("https://api.favcircles.com/s/OTHER9?t=table-7") == .otherStore)
        #expect(match("https://example.com/menu") == .other)
        #expect(match("not a link") == .other)
        #expect(NFCStickerLink.match("https://api.favcircles.com/s/WIN123?t=a", windowUrl: nil, knownTags: ["a"]) == .otherStore)
    }

    @Test func tapsLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = ISO8601DateFormatter().date(from: "2026-11-01T18:00:00Z")!
        let earlier = now.addingTimeInterval(-3600)
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(NFCStickerLink.tapsLine(taps: 0, lastTap: nil, written: false, locked: false, now: now, calendar: calendar) == "Not written yet")
        #expect(NFCStickerLink.tapsLine(taps: 0, lastTap: nil, written: true, locked: false, now: now, calendar: calendar) == "0 taps")
        #expect(NFCStickerLink.tapsLine(taps: 1, lastTap: earlier, written: true, locked: false, now: now, calendar: calendar) == "1 tap \u{00B7} last today")
        #expect(NFCStickerLink.tapsLine(taps: 12, lastTap: yesterday, written: true, locked: true, now: now, calendar: calendar) == "12 taps \u{00B7} last yesterday \u{00B7} locked")
    }
}
