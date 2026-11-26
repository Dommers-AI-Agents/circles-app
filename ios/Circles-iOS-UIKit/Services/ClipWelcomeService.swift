import Foundation

/// A store's App Clip screens after Open (Welcome, sign-in, connected), as
/// the owner sees and edits them (backend/services/clipExperience.js,
/// 2026-11-26). Changes show at the next scan; no app update needed.
struct ClipWelcomeSettings: Decodable {
    struct Overrides: Decodable {
        let shortName: String?
        let welcomeLine: String?
        let doneLine: String?
        let rows: [String]?
        let showRewards: Bool?
        let showWallet: Bool?
        let connectPhotoUrl: String?
        let menuUrl: String?
    }
    struct Row: Decodable { let kind: String; let title: String; let detail: String }
    struct Welcome: Decodable { let title: String; let line: String; let rows: [Row]; let button: String; let photoUrl: String? }
    struct Connect: Decodable { let photoUrl: String? }
    struct Done: Decodable { let line: String; let showRewards: Bool; let showWallet: Bool }
    struct Experience: Decodable { let shortName: String; let welcome: Welcome; let connect: Connect; let done: Done }

    let overrides: Overrides
    let experience: Experience
    let photos: [String]
    let rowKinds: [String]
    let rewardsLive: Bool
}

final class ClipWelcomeService {
    static let shared = ClipWelcomeService()
    private let api = APIService.shared
    private struct Envelope<T: Decodable>: Decodable { let data: T }

    func load(venueId: String, completion: @escaping (Result<ClipWelcomeSettings, APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/clip-welcome", method: .get, requiresAuth: true) { (r: Result<Envelope<ClipWelcomeSettings>, APIError>) in
            completion(r.map(\.data))
        }
    }

    /// Only the fields given change; NSNull() puts one back to the default
    func update(venueId: String, _ fields: [String: Any], completion: @escaping (Result<ClipWelcomeSettings, APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/clip-welcome", method: .put, body: fields, requiresAuth: true) { (r: Result<Envelope<ClipWelcomeSettings>, APIError>) in
            completion(r.map(\.data))
        }
    }
}
