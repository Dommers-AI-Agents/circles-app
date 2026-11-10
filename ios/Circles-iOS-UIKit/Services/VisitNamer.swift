import UIKit

/// Names visits that are still called by their street address (Wes,
/// 2026-11-10: "Can't they save the names of places?").
///
/// A visit is recorded when iOS wakes the app for a few seconds after you
/// leave, and the Apple Maps lookup often doesn't finish then. So naming
/// happens again later, with the app open: after the visit list loads, and
/// once every few hours when the app comes to the front. A failed lookup is
/// tried again next time; "no business close enough" waits a week.
final class VisitNamer {
    static let shared = VisitNamer()

    /// visit id → when Apple Maps last found no clear business there
    private let noMatchKey = "visitNamingNoMatch"
    private let lastPassKey = "visitNamingLastPass"
    static let retryNoMatchAfter: TimeInterval = 7 * 86_400
    static let foregroundPassEvery: TimeInterval = 6 * 3_600
    /// Apple Maps allows ~50 lookups a minute; stay well under it
    static let perPass = 25
    static let pace: TimeInterval = 1.5

    private var queue: [PlaceVisit] = []
    private var queued = Set<String>()
    private var running = false
    private var observing = false

    private init() {}

    /// Called once at launch: a pass whenever the app comes to the front
    func start() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.foregroundPass() }
    }

    /// The recent visits from the server, named where they still need it
    func foregroundPass() {
        guard UIApplication.shared.applicationState == .active,
              AuthService.shared.getUserId() != nil else { return }
        let now = Date().timeIntervalSince1970
        guard now - UserDefaults.standard.double(forKey: lastPassKey) > Self.foregroundPassEvery else { return }
        UserDefaults.standard.set(now, forKey: lastPassKey)
        APIService.shared.request(endpoint: "visits", method: .get, queryParams: ["limit": "100"],
                                  requiresAuth: true) { [weak self] (result: Result<VisitsResponse, APIError>) in
            guard case .success(let response) = result else { return }
            DispatchQueue.main.async { self?.name(response.data.map { PlaceVisit.from($0) }) }
        }
    }

    /// Looks up the ones still named for their address, a few at a time.
    /// Each one named posts `.visitRenamed` with the updated visit.
    func name(_ visits: [PlaceVisit]) {
        let tried = noMatches()
        let now = Date()
        let due = visits.filter { visit in
            guard visit.synced, VisitPlaceSuggestion.needsName(visit), !queued.contains(visit.id) else { return false }
            guard let last = tried[visit.id] else { return true }
            return now.timeIntervalSince1970 - last > Self.retryNoMatchAfter
        }
        for visit in due.prefix(max(0, Self.perPass - queue.count)) {
            queue.append(visit)
            queued.insert(visit.id)
        }
        runNext()
    }

    private func runNext() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let visit = queue.removeFirst()
        VisitPlaceSuggester.candidatesResult(latitude: visit.latitude, longitude: visit.longitude) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                // Throttled or offline: stop here; the next pass tries again
                self.queue.forEach { self.queued.remove($0.id) }
                self.queue.removeAll()
                self.finish(visit, after: 0)
            case .success(let candidates):
                guard let best = VisitPlaceSuggestion.autoName(from: candidates, accuracy: visit.horizontalAccuracy) else {
                    self.markNoMatch(visit.id)
                    return self.finish(visit, after: Self.pace)
                }
                self.save(best, to: visit) { self.finish(visit, after: Self.pace) }
            }
        }
    }

    private func finish(_ visit: PlaceVisit, after delay: TimeInterval) {
        queued.remove(visit.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.running = false
            self?.runNext()
        }
    }

    private func save(_ best: VisitPlaceSuggestion.Candidate, to visit: PlaceVisit, then: @escaping () -> Void) {
        var updates: [String: Any] = ["placeName": best.name]
        if !best.address.isEmpty { updates["placeAddress"] = best.address }
        if let category = best.category { updates["category"] = category }
        APIService.shared.request(endpoint: "visits/\(visit.id)", method: .put, body: updates,
                                  requiresAuth: true) { (result: Result<VisitResponse, APIError>) in
            DispatchQueue.main.async {
                if case .success = result {
                    var named = visit
                    named.placeName = best.name
                    if !best.address.isEmpty { named.placeAddress = best.address }
                    if let category = best.category { named.category = category }
                    Logger.info("📍 Named visit \(visit.id): \(visit.placeName) → \(best.name)")
                    NotificationCenter.default.post(name: .visitRenamed, object: nil, userInfo: ["visit": named])
                }
                then()
            }
        }
    }

    private func noMatches() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: noMatchKey) as? [String: Double] ?? [:]
    }

    private func markNoMatch(_ id: String) {
        var tried = noMatches()
        tried[id] = Date().timeIntervalSince1970
        // Only a retry timer, not the person's data: forget stamps past their week
        let cutoff = Date().timeIntervalSince1970 - Self.retryNoMatchAfter
        tried = tried.filter { $0.value > cutoff }
        UserDefaults.standard.set(tried, forKey: noMatchKey)
    }
}
