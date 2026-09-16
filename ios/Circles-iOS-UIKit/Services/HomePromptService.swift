import Foundation

/// Home "daily card" API. The server picks the card and remembers what this
/// user has seen; the app fetches, renders, and acks Skip / tap.
final class HomePromptService {
    static let shared = HomePromptService()
    private init() {}

    /// The one key both postcard nudges share. The server treats it as a
    /// client-ackable key, so the app's post-save pop-up can spend the
    /// fortnightly cooldown that also governs the home card.
    static let postcardNudgeKey = "postcard_nudge"

    private struct PromptResponse: Decodable {
        let success: Bool
        let card: HomePromptCard?
    }

    enum Action: String { case skipped, acted }

    /// `nil` card means "nothing today" — a normal outcome, not an error.
    func fetch(completion: @escaping (Result<HomePromptCard?, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "home/prompt",
            method: .get,
            requiresAuth: true
        ) { (result: Result<PromptResponse, APIError>) in
            switch result {
            case .success(let response): completion(.success(response.card))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Fire-and-forget: a lost ack costs one repeat of a dynamic card at most.
    func ack(key: String, action: Action) {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        APIService.shared.request(
            endpoint: "home/prompt/\(encoded)/ack",
            method: .post,
            body: ["action": action.rawValue],
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            if case .failure(let error) = result {
                Logger.debug("🃏 home prompt ack failed for \(key): \(error)")
            }
        }
    }
}
