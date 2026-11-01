import Foundation
import Testing
@testable import Circles_iOS

/// "Oops, something went wrong" after every successful save (Wes,
/// 2026-11-01): the app required a `user` the server never sent. The reply
/// now reads as success with or without it, and every setting goes up.
struct NotificationPreferencesSaveTests {
    private let reply = """
    {"success":true,"message":"Notification preferences updated successfully",
     "user":{"_id":"u1","email":"w@x.com","displayName":"Wes","profilePicture":null,"bio":null,"location":"Charlotte, NC",
             "zipcode":null,"followersCount":3,"followingCount":2,"preferences":null,
             "notificationPreferences":{"newMessages":false,"dailyQuote":true}}}
    """

    @Test func theReplyReadsAsSuccess() throws {
        let simple = try JSONDecoder().decode(SimpleAPIResponse.self, from: Data(#"{"success":true,"message":"ok"}"#.utf8))
        #expect(simple.success)
        let withUser = try JSONDecoder().decode(SimpleAPIResponse.self, from: Data(reply.utf8))
        #expect(withUser.success)
    }

    @Test func olderAppsCanReadTheUserInTheReply() throws {
        let response = try JSONDecoder().decode(UserResponse.self, from: Data(reply.utf8))
        #expect(response.user.notificationPreferences?.newMessages == false)
    }

    @Test func everySettingIsSent() throws {
        var prefs = NotificationPreferences()
        prefs.locationPrompts = false
        let data = try JSONEncoder().encode(prefs)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["locationPrompts"] as? Bool == false)
        #expect(body["storeAlerts"] != nil)
        #expect(body["quietHoursEnd"] != nil)
    }
}
