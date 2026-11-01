import Foundation

/// Who sent a chat push, read from its payload, so the Notification Service
/// Extension can show it as a message from a person (their photo on the
/// banner, Focus breakthrough for people you talk to) instead of an app
/// alert (2026-11-01). Pure; compiled into the app (tested) and into
/// Circles-NotificationService.
enum CommunicationPush {

    /// Push types that are a message from one person
    static let messageTypes: Set<String> = ["new_message"]

    struct Sender: Equatable {
        let senderId: String
        let name: String
        let avatarURL: URL?
        /// Threads the banners per chat
        let conversationId: String?

        init?(userInfo: [AnyHashable: Any]) {
            guard let type = userInfo["type"] as? String, CommunicationPush.messageTypes.contains(type),
                  let senderId = (userInfo["senderId"] as? String).flatMap(CommunicationPush.nonEmpty) else { return nil }
            let name = (userInfo["senderName"] as? String).flatMap(CommunicationPush.nonEmpty)
            self.senderId = senderId
            self.name = name ?? "Someone"
            self.avatarURL = (userInfo["senderPhoto"] as? String).flatMap(CommunicationPush.webURL)
            self.conversationId = (userInfo["conversationId"] as? String).flatMap(CommunicationPush.nonEmpty)
        }
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Only http(s) photos are fetched
    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}
