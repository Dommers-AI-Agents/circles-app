import Foundation
import UIKit

/// Quietly resolves unmapped imported places while the app is foregrounded.
///
/// Large Google Takeout imports only resolve their first ~40 rows inline
/// (see `AppleImportResolver.resolve(limit:)`) — the rest import unmapped
/// with `needsResolution` set on the backend. This queue picks those up:
/// fetch the caller's unresolved places, locate each via the same polite
/// one-at-a-time Apple Maps search the inline pass uses, and PUT the
/// coordinate back. No UI while it works; when a pass finishes it refreshes
/// circle lists, and if any newly-located place turned out to duplicate an
/// existing save, it offers a mass-delete review sheet.
///
/// Kicked from post-launch setup (after auth), app foregrounding, and right
/// after a successful import. Pauses cleanly when the app backgrounds —
/// MKLocalSearch work doesn't belong in the background, and the backend
/// keeps `needsResolution` until we succeed, so nothing is lost.
final class ImportResolutionQueue {

    static let shared = ImportResolutionQueue()

    // MARK: - Models

    private struct UnresolvedPlace: Decodable {
        let id: String
        let name: String
        let address: String?
        let circleId: String?
    }

    private struct UnresolvedResponse: Decodable {
        struct Payload: Decodable {
            let places: [UnresolvedPlace]
            let count: Int
        }
        let success: Bool
        let data: Payload
    }

    private struct ResolveResponse: Decodable {
        struct DuplicateTarget: Decodable {
            let placeId: String
            let name: String
            let circleId: String?
            let circleName: String?
        }
        struct Payload: Decodable {
            let placeId: String
            let globalPlaceId: String?
            let address: String?
            let duplicateOf: DuplicateTarget?
        }
        let success: Bool
        let data: Payload
    }

    // MARK: - State

    private var isRunning = false
    /// Set when the app backgrounds mid-pass; the current step checks it and
    /// stops without advancing. Foregrounding kicks a fresh pass, which
    /// re-fetches whatever is still unresolved.
    private var shouldStop = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    // MARK: - Lifecycle

    @objc private func appDidEnterBackground() {
        shouldStop = true
    }

    @objc private func appWillEnterForeground() {
        kick()
    }

    /// Starts a resolution pass if one isn't already running. Safe to call
    /// often — it no-ops when running, logged out, or backgrounded, and an
    /// empty unresolved list ends the pass immediately.
    func kick() {
        DispatchQueue.main.async {
            guard !self.isRunning else { return }
            guard AuthService.shared.isLoggedIn else { return }
            guard UIApplication.shared.applicationState != .background else { return }

            self.isRunning = true
            self.shouldStop = false
            self.fetchUnresolved()
        }
    }

    // MARK: - Pass

    private func fetchUnresolved() {
        APIService.shared.request(
            endpoint: "places/unresolved",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UnresolvedResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response) where !response.data.places.isEmpty:
                    Logger.debug("📍 ImportResolutionQueue: resolving \(response.data.places.count) unmapped place(s)")
                    self.process(places: response.data.places)
                case .success:
                    self.isRunning = false
                case .failure(let error):
                    Logger.debug("📍 ImportResolutionQueue: unresolved fetch failed — \(error.localizedDescription)")
                    self.isRunning = false
                }
            }
        }
    }

    private func process(places: [UnresolvedPlace]) {
        var index = 0
        var resolvedCount = 0
        var duplicates: [ImportDuplicate] = []

        func finishPass(interrupted: Bool) {
            isRunning = false
            Logger.debug("📍 ImportResolutionQueue: pass \(interrupted ? "paused" : "done") — \(resolvedCount) resolved, \(duplicates.count) duplicate(s)")
            guard !interrupted else { return }
            if resolvedCount > 0 {
                NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
            }
            if !duplicates.isEmpty {
                presentDuplicateReview(duplicates)
            }
        }

        func processNext(throttleRetry: Int = 0) {
            guard !shouldStop else {
                finishPass(interrupted: true)
                return
            }
            guard index < places.count else {
                finishPass(interrupted: false)
                return
            }
            let place = places[index]

            // A backend-stamped placeholder address adds nothing to the query
            let address = place.address == "Address pending" ? nil : place.address
            AppleImportResolver.searchVenue(name: place.name, address: address) { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case .throttled where throttleRetry < AppleImportResolver.maxThrottleRetries:
                        // Same item, not advanced — backed off, exactly like
                        // the inline pass
                        let delay = AppleImportResolver.throttleDelay(retry: throttleRetry)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            processNext(throttleRetry: throttleRetry + 1)
                        }
                    case .resolved(let match):
                        self.resolve(place: place, match: match) { duplicate in
                            if let duplicate = duplicate {
                                duplicates.append(duplicate)
                            }
                            resolvedCount += 1
                            index += 1
                            DispatchQueue.main.asyncAfter(deadline: .now() + AppleImportResolver.interRequestDelay) {
                                processNext()
                            }
                        }
                    case .notFound:
                        // Genuinely not found — record the strike so the
                        // backend retires rows after three failed passes
                        // (saved Takeout articles never resolve). Best-effort;
                        // the pass moves on regardless.
                        self.reportNotFound(placeId: place.id)
                        index += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + AppleImportResolver.interRequestDelay) {
                            processNext()
                        }
                    case .throttled:
                        // Throttled past the retry budget — NOT a strike;
                        // leave unmapped for a future pass
                        index += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + AppleImportResolver.interRequestDelay) {
                            processNext()
                        }
                    }
                }
            }
        }

        processNext()
    }

    /// Writes a located coordinate back to the save record. Calls back with
    /// the duplicate collision, if the backend reports that this place — now
    /// that it has a location — matches another of the user's saves. The
    /// just-resolved place is the newcomer (delete candidate); `duplicateOf`
    /// is the older save to keep.
    private func resolve(
        place: UnresolvedPlace,
        match: AppleImportResolver.VenueMatch,
        completion: @escaping (ImportDuplicate?) -> Void
    ) {
        var body: [String: Any] = [
            "latitude": match.latitude,
            "longitude": match.longitude
        ]
        if let address = match.formattedAddress {
            body["address"] = address
        }
        if let category = match.applePoiCategory {
            body["applePoiCategory"] = category
        }

        APIService.shared.request(
            endpoint: "places/\(place.id)/resolve",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<ResolveResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    guard let target = response.data.duplicateOf else {
                        completion(nil)
                        return
                    }
                    completion(ImportDuplicate(
                        placeId: place.id,
                        placeName: place.name,
                        keeperName: target.name,
                        keeperCircleName: target.circleName
                    ))
                case .failure(let error):
                    // Leave unmapped; a later pass retries it
                    Logger.debug("📍 ImportResolutionQueue: resolve failed for \(place.name) — \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }

    /// Tells the backend an Apple search came up empty for this place, so
    /// three-strike rows leave the retry feed. Fire-and-forget.
    private func reportNotFound(placeId: String) {
        APIService.shared.request(
            endpoint: "places/\(placeId)/resolve",
            method: .put,
            body: ["notFound": true],
            requiresAuth: true
        ) { (_: Result<SimpleAPIResponse, APIError>) in }
    }

    // MARK: - Duplicate review

    private func presentDuplicateReview(_ duplicates: [ImportDuplicate]) {
        guard let topViewController = getTopViewController(),
              !(topViewController is UIAlertController) else {
            // Awkward moment (alert up, mid-flow) — the duplicates stay
            // deletable from their circles; don't fight for the screen
            Logger.debug("📍 ImportResolutionQueue: skipped duplicate review — no clean presenter")
            return
        }
        let reviewVC = DuplicateReviewViewController(duplicates: duplicates)
        let navController = UINavigationController(rootViewController: reviewVC)
        topViewController.present(navController, animated: true)
    }

    private func getTopViewController() -> UIViewController? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           var topController = window.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        }
        return nil
    }
}
