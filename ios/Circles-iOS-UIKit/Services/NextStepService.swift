import Foundation

/// Phase 4 of "never a dead end" (2026-11-02): this person's next-step order
/// from the server (GET /api/next-steps), kept for 30 minutes, and every
/// step shown or tapped reported back (POST /api/next-steps/events) so the
/// ones they keep skipping sink. Works without it: the moment's own order.
final class NextStepService {
    static let shared = NextStepService()

    private(set) var order: [String] = []
    private(set) var boost: [String] = []
    private(set) var avoid: Set<String> = []
    private var fetchedAt: Date?
    private var fetching = false

    private struct Ranking: Decodable {
        let order: [String]
        let boost: [String]?
        let avoid: [String]?
    }
    private struct RankingResponse: Decodable { let success: Bool; let data: Ranking }

    /// Fetch when there's none or it's older than 30 minutes
    func refreshIfStale() {
        guard AuthService.shared.isLoggedIn, !fetching,
              fetchedAt.map({ Date().timeIntervalSince($0) > 1800 }) ?? true else { return }
        fetching = true
        APIService.shared.request(endpoint: "next-steps", method: .get) { [weak self] (result: Result<RankingResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                guard case .success(let response) = result else { return }
                self.order = response.data.order
                self.boost = response.data.boost ?? []
                self.avoid = Set(response.data.avoid ?? [])
                self.fetchedAt = Date()
            }
        }
    }

    /// Fire and forget: one step shown or tapped
    func record(_ steps: [NextStep], surface: String, kind: String) {
        guard AuthService.shared.isLoggedIn, !steps.isEmpty else { return }
        let events = steps.map { ["step": $0.id, "surface": surface, "kind": kind] }
        APIService.shared.request(endpoint: "next-steps/events", method: .post, body: ["events": events]) { (_: Result<SimpleResponse, APIError>) in }
    }

    /// Clear on sign-out: the next person's order is their own
    func reset() {
        order = []; boost = []; avoid = []; fetchedAt = nil
    }
}
