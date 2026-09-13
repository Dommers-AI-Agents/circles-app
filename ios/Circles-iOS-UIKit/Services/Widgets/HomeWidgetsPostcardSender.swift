import Foundation
import FavWidgetsCore

/// Delivers a postcard from the Widgets tab: uploads the rendered image
/// through the existing image endpoint, then asks the server to drop it
/// into the recipient's conversation (push + chat bubble).
enum HomeWidgetsPostcardSender {
    private struct SendResponse: Decodable {
        let success: Bool
        let messageId: String
        let conversationId: String
        let piggyBank: PiggyBankCredit?
    }

    static func send(_ postcard: WidgetPostcardSend) async throws -> WidgetPostcardReceipt {
        let imageUrl = try await upload(postcard.imageJPEG)

        var body: [String: Any] = [
            "recipientId": postcard.recipientId,
            "imageUrl": imageUrl,
            "message": postcard.message,
            "templateId": postcard.templateId
        ]
        if let place = postcard.place {
            var ref: [String: Any] = ["name": place.name]
            if let city = place.city { ref["city"] = city }
            if place.isGlobal { ref["globalPlaceId"] = place.id }
            body["placeRef"] = ref
        }

        let response: SendResponse = try await withCheckedThrowingContinuation { continuation in
            APIService.shared.request(endpoint: "widgets/postcard/send", method: .post, body: body, requiresAuth: true) { (result: Result<SendResponse, APIError>) in
                continuation.resume(with: result)
            }
        }
        PiggyBankDepositView.play(credit: response.piggyBank)
        return WidgetPostcardReceipt(messageId: response.messageId, conversationId: response.conversationId, imageURL: URL(string: imageUrl))
    }

    private static func upload(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            PlaceService.shared.uploadImage(data) { result in
                continuation.resume(with: result)
            }
        }
    }
}
