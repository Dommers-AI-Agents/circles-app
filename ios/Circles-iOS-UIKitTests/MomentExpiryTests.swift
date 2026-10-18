import Foundation
import Testing
@testable import Circles_iOS

/// Disappearing moments (2026-10-18): the countdown on them and dropping the
/// ones that ran out from lists the app already has.
struct MomentExpiryTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func ordinaryMomentsNeverExpireOrShowABadge() {
        #expect(!MomentExpiry.isExpired(nil, now: now))
        #expect(MomentExpiry.badge(nil, now: now) == nil)
    }

    @Test func countdownInHoursThenMinutes() {
        #expect(MomentExpiry.timeLeft(now.addingTimeInterval(23 * 3600 + 59 * 60), now: now) == "23h left")
        #expect(MomentExpiry.timeLeft(now.addingTimeInterval(3600), now: now) == "1h left")
        #expect(MomentExpiry.timeLeft(now.addingTimeInterval(45 * 60 + 30), now: now) == "45m left")
        #expect(MomentExpiry.timeLeft(now.addingTimeInterval(20), now: now) == "<1m left")
        #expect(MomentExpiry.badge(now.addingTimeInterval(5 * 3600), now: now) == "\u{23F1} 5h left")
    }

    @Test func goneOnceTheTimePasses() {
        #expect(MomentExpiry.isExpired(now, now: now))
        #expect(MomentExpiry.isExpired(now.addingTimeInterval(-1), now: now))
        #expect(!MomentExpiry.isExpired(now.addingTimeInterval(1), now: now))
        #expect(MomentExpiry.badge(now.addingTimeInterval(-60), now: now) == nil)
    }

    @Test func decodesExpiresAtAndListsDropTheGoneOnes() throws {
        func moment(_ id: String, expiresAt: String?) -> String {
            let expiry = expiresAt.map { #","expiresAt":"\#($0)""# } ?? ""
            return #"{"_id":"\#(id)","userId":"u","placeId":"p","placeName":"Cafe","title":"t","description":"","visibility":"public","viewCount":0,"likeCount":0,"commentCount":0,"tags":[],"uploadStatus":"ready","createdAt":"2026-10-18T10:00:00.000Z","updatedAt":"2026-10-18T10:00:00.000Z"\#(expiry)}"#
        }
        let json = "[" + [moment("gone", expiresAt: "2026-10-18T11:00:00.000Z"),
                          moment("live", expiresAt: "2026-10-19T11:00:00.000Z"),
                          moment("plain", expiresAt: nil)].joined(separator: ",") + "]"
        // Like the app's decoder: ISO 8601 with milliseconds
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            guard let date = iso.date(from: text) else { throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: text)) }
            return date
        }
        let videos = try decoder.decode([PlaceVideo].self, from: Data(json.utf8))
        #expect(videos[0].expiresAt != nil && videos[2].expiresAt == nil)
        let noon = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
        #expect(MomentExpiry.visible(videos, now: noon).map(\.id) == ["live", "plain"])
    }
}
