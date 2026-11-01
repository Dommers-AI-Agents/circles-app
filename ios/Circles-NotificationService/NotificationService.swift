import Intents
import UserNotifications

/// Turns a chat push into a communication notification: the sender's photo
/// and name on the banner, the way Messages shows them, and Focus can let
/// people you talk to through (2026-11-01). Every other push passes through
/// unchanged.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let sender = CommunicationPush.Sender(userInfo: request.content.userInfo) else {
            contentHandler(request.content)
            return
        }
        bestAttempt = content
        Self.loadAvatar(sender.avatarURL) { [weak self] image in
            self?.deliver(Self.communicationContent(content, sender: sender, image: image))
        }
    }

    /// Out of time: the plain banner, never nothing
    override func serviceExtensionTimeWillExpire() {
        if let bestAttempt { deliver(bestAttempt) }
    }

    private func deliver(_ content: UNNotificationContent) {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(content)
    }

    private static func communicationContent(_ content: UNMutableNotificationContent,
                                             sender: CommunicationPush.Sender,
                                             image: INImage?) -> UNNotificationContent {
        let person = INPerson(personHandle: INPersonHandle(value: sender.senderId, type: .unknown),
                              nameComponents: nil,
                              displayName: sender.name,
                              image: image,
                              contactIdentifier: nil,
                              customIdentifier: sender.senderId)
        let intent = INSendMessageIntent(recipients: nil,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: content.body,
                                         speakableGroupName: nil,
                                         conversationIdentifier: sender.conversationId,
                                         serviceName: nil,
                                         sender: person,
                                         attachments: nil)
        if let image { intent.setImage(image, forParameterNamed: \.sender) }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        // The person's name becomes the title, so the server's "💬 Name" goes
        return (try? content.updating(from: intent)) ?? content
    }

    private static func loadAvatar(_ url: URL?, completion: @escaping (INImage?) -> Void) {
        guard let url else { return completion(nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            completion(ok ? data.map { INImage(imageData: $0) } : nil)
        }.resume()
    }
}
