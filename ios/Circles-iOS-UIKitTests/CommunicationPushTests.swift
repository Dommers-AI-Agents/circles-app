import Foundation
import Testing
@testable import Circles_iOS

/// Chat pushes become communication notifications (sender photo + name)
struct CommunicationPushTests {

    private let message: [AnyHashable: Any] = [
        "type": "new_message", "senderId": "u1", "senderName": "Sal",
        "senderPhoto": "https://cdn.example.com/sal.jpg", "conversationId": "c9"
    ]

    @Test func readsTheSender() {
        let sender = CommunicationPush.Sender(userInfo: message)
        #expect(sender?.senderId == "u1")
        #expect(sender?.name == "Sal")
        #expect(sender?.avatarURL?.absoluteString == "https://cdn.example.com/sal.jpg")
        #expect(sender?.conversationId == "c9")
    }

    @Test func onlyMessagesFromSomeone() {
        var other = message
        other["type"] = "place_like"
        #expect(CommunicationPush.Sender(userInfo: other) == nil)
        var anonymous = message
        anonymous["senderId"] = "  "
        #expect(CommunicationPush.Sender(userInfo: anonymous) == nil)
    }

    @Test func missingNameAndBadPhoto() {
        var info = message
        info["senderName"] = ""
        info["senderPhoto"] = "file:///etc/passwd"
        info["conversationId"] = nil
        let sender = CommunicationPush.Sender(userInfo: info)
        #expect(sender?.name == "Someone")
        #expect(sender?.avatarURL == nil)
        #expect(sender?.conversationId == nil)
    }
}
