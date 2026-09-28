import Testing
import Foundation
@testable import Circles_iOS

/// What the in-app scanner accepts: the store sticker links the iPhone
/// Camera app would open, and nothing else.
struct StickerCodeExtractorTests {

    @Test func readsTheStickerLink() {
        #expect(StickerCodeExtractor.code(from: "https://api.favcircles.com/s/AB12CD") == "AB12CD")
    }

    @Test func readsTheLegacyHostAndTrimsWhitespace() {
        #expect(StickerCodeExtractor.code(from: "  https://circles-backend-196924649787.us-central1.run.app/s/xyz9\n") == "xyz9")
    }

    @Test func rejectsOtherQRCodes() {
        #expect(StickerCodeExtractor.code(from: "https://example.com/s/AB12CD") == nil)
        #expect(StickerCodeExtractor.code(from: "https://api.favcircles.com/app/circle/c1") == nil)
        #expect(StickerCodeExtractor.code(from: "https://api.favcircles.com/s/") == nil)
        #expect(StickerCodeExtractor.code(from: "WIFI:S:Cafe;T:WPA;P:secret;;") == nil)
        #expect(StickerCodeExtractor.code(from: "just some text") == nil)
        #expect(StickerCodeExtractor.code(from: "") == nil)
    }
}
