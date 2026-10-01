import Testing
import Foundation
@testable import Circles_iOS

/// The in-app Notifications list: every row decodes, has an icon, and opens
/// what its push opens.
struct NotificationListRowTests {

    private func decode(_ json: String) throws -> AppNotification {
        try JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
    }

    @Test func aHowAreYouInvitationRowOpensTheWidget() throws {
        let row = try decode(#"{"id":"n1","userId":"amanda","type":"care_watcher_invite","title":"Wes invited you","body":"Check in on Sal","read":false,"archived":false,"createdAt":"2026-10-01T10:00:00Z","data":{"type":"care_watcher_invite","planId":"p1"}}"#)
        var info: [AnyHashable: Any] = row.data?.raw ?? [:]
        info["type"] = row.type
        #expect(row.data?.raw["planId"] == "p1")
        #expect(NotificationTapRouter.destination(for: info) != nil)
        #expect(NotificationRowStyle.style(for: row.type).symbol == "heart.text.square.fill")
    }

    @Test func aNonStringFieldNoLongerBreaksThePage() throws {
        let row = try decode(#"{"id":"n2","userId":"u","type":"milestone","title":"🥈","body":"b","read":true,"createdAt":"x","data":{"position":2,"placeCount":"14","milestoneType":"top_contributor","fromUserId":"f","flag":true}}"#)
        #expect(row.data?.raw["position"] == "2")
        #expect(row.data?.raw["flag"] == "true")
        #expect(row.data?.fromUserId == "f")
    }

    @Test func everyKnownKindHasItsOwnIcon() {
        for type in ["place_like", "new_message", "milestone", "nextbar_round", "postcard_order", "fridgemail", "care_invite", "care_silence", "check_in_response"] {
            #expect(NotificationRowStyle.style(for: type).symbol != "bell.fill", "\(type)")
        }
        #expect(NotificationRowStyle.style(for: "something_new").symbol == "bell.fill")
    }
}
