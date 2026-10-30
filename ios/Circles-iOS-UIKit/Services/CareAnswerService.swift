import Foundation

/// The one path that answers a How Are You? question: the notification's
/// buttons, the Lock Screen display's buttons, and their typed 0–10 / words.
enum CareAnswerService {
    /// - Parameter body: `["answer": choiceKey]` or `["value": number or words]`, plus `note`.
    static func send(askId: String, body: [String: Any], completion: @escaping (Bool) -> Void) {
        APIService.shared.request(
            endpoint: "widgets/care/asks/\(askId)/answer",
            method: .post,
            body: body
        ) { (result: Result<EmptyResponse, APIError>) in
            if case .failure(let error) = result { Logger.debug("❌ Care answer failed: \(error)") }
            if case .success = result { completion(true) } else { completion(false) }
        }
    }

    static func send(askId: String, body: [String: Any]) async -> Bool {
        await withCheckedContinuation { continuation in
            send(askId: askId, body: body) { continuation.resume(returning: $0) }
        }
    }
}
