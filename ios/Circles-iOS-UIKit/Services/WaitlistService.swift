import Foundation

/// A store's waitlist, both sides (2026-11-09). Customer calls go to
/// /api/waitlist; the host's to /api/rewards/venues/:id/waitlist.
final class WaitlistService {
    static let shared = WaitlistService()
    private let api = APIService.shared
    private init() {}

    private struct Envelope<T: Codable>: Codable { let success: Bool; let data: T }
    private struct MineData: Codable { let entry: WaitlistEntry? }
    private struct LeftData: Codable { let left: Bool; let status: String? }
    struct HostData: Codable { let settings: StoreWaitlist; let line: [WaitlistEntry] }
    private struct SettingsData: Codable { let settings: StoreWaitlist }

    // MARK: Customer

    func join(venueId: String, partySize: Int, completion: @escaping (Result<WaitlistEntry, APIError>) -> Void) {
        api.request(endpoint: "waitlist/\(venueId)/join", method: .post, body: ["partySize": partySize], requiresAuth: true) {
            (r: Result<Envelope<WaitlistEntry>, APIError>) in completion(r.map(\.data))
        }
    }

    func mine(venueId: String, completion: @escaping (Result<WaitlistEntry?, APIError>) -> Void) {
        api.request(endpoint: "waitlist/\(venueId)/mine", method: .get, requiresAuth: true) {
            (r: Result<Envelope<MineData>, APIError>) in completion(r.map(\.data.entry))
        }
    }

    func leave(entryId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        api.request(endpoint: "waitlist/entries/\(entryId)/leave", method: .post, body: [:], requiresAuth: true) {
            (r: Result<Envelope<LeftData>, APIError>) in completion(r.map { _ in () })
        }
    }

    // MARK: Host

    func storeLine(venueId: String, completion: @escaping (Result<HostData, APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/waitlist", method: .get, requiresAuth: true) {
            (r: Result<Envelope<HostData>, APIError>) in completion(r.map(\.data))
        }
    }

    func saveSettings(venueId: String, settings: StoreWaitlist, completion: @escaping (Result<StoreWaitlist, APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/waitlist", method: .put,
                    body: ["enabled": settings.enabled, "quoteMinutes": settings.quoteMinutes], requiresAuth: true) {
            (r: Result<Envelope<SettingsData>, APIError>) in completion(r.map(\.data.settings))
        }
    }

    enum HostAction: String { case notify, seat, remove }

    func act(venueId: String, entryId: String, action: HostAction, completion: @escaping (Result<WaitlistEntry, APIError>) -> Void) {
        api.request(endpoint: "rewards/venues/\(venueId)/waitlist/\(entryId)/\(action.rawValue)", method: .post, body: [:], requiresAuth: true) {
            (r: Result<Envelope<WaitlistEntry>, APIError>) in completion(r.map(\.data))
        }
    }
}
