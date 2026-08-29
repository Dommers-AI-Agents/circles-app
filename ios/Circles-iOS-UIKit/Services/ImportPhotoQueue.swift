import Foundation
import MapKit
import UIKit

/// Background pass that gives imported places a photo for free.
///
/// Imports (Google Maps lists, Takeout, Mapstr, Swarm) never spend on Google
/// photos, so they arrive photo-less. Apple Look Around snapshots are free and
/// on-device, so whenever the app is in the foreground this queue asks the
/// backend for own imported places without a photo, renders a Look Around
/// snapshot at each pin, uploads it through the normal image path, and
/// attaches it — the same thing Add Place does inline for a single place.
///
/// Mirrors ImportResolutionQueue: sequential, pauses when the app backgrounds,
/// re-fetches on foreground, and a place with no Look Around coverage is
/// recorded as a strike server-side so it isn't retried forever.
final class ImportPhotoQueue {

    static let shared = ImportPhotoQueue()

    private struct PhotoCandidate: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lng: Double
    }

    private struct CandidatesResponse: Decodable {
        struct Payload: Decodable {
            let places: [PhotoCandidate]
            let count: Int
        }
        let success: Bool
        let data: Payload
    }

    private struct FallbackResponse: Decodable {
        struct Payload: Decodable {
            let placeId: String
            let applied: Bool
        }
        let success: Bool
        let data: Payload
    }

    /// Per-pass cap: each item is a Look Around render + an upload (~1–3s)
    private static let maxPerPass = 40
    private static let snapshotSize = CGSize(width: 900, height: 600)

    private var isRunning = false
    private var shouldStop = false

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() { shouldStop = true }
    @objc private func appWillEnterForeground() { kick() }

    /// Safe to call often — no-ops when already running, logged out, or
    /// backgrounded; an empty candidate list ends the pass immediately.
    func kick() {
        DispatchQueue.main.async {
            guard #available(iOS 16.0, *) else { return }
            guard !self.isRunning else { return }
            guard AuthService.shared.isLoggedIn else { return }
            guard UIApplication.shared.applicationState != .background else { return }
            self.isRunning = true
            self.shouldStop = false
            self.fetchCandidates()
        }
    }

    private func fetchCandidates() {
        APIService.shared.request(
            endpoint: "places/needs-photo",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CandidatesResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response) where !response.data.places.isEmpty:
                    Logger.debug("📸 ImportPhotoQueue: \(response.data.count) imported place(s) without a photo")
                    self.process(Array(response.data.places.prefix(Self.maxPerPass)))
                case .success:
                    self.isRunning = false
                case .failure(let error):
                    Logger.debug("📸 ImportPhotoQueue: candidate fetch failed — \(error.localizedDescription)")
                    self.isRunning = false
                }
            }
        }
    }

    @available(iOS 16.0, *)
    private func process(_ places: [PhotoCandidate]) {
        var index = 0
        var applied = 0

        func finish(interrupted: Bool) {
            isRunning = false
            Logger.debug("📸 ImportPhotoQueue: pass \(interrupted ? "paused" : "done") — \(applied) photo(s) attached")
            if applied > 0, !interrupted {
                NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
            }
        }

        func next() {
            guard !shouldStop else { finish(interrupted: true); return }
            guard index < places.count else { finish(interrupted: false); return }
            let place = places[index]
            index += 1
            let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)

            Task {
                var image: UIImage?
                if await AppleLookAroundService.shared.checkLookAroundAvailability(at: coordinate) {
                    image = try? await AppleLookAroundService.shared.getLookAroundSnapshot(at: coordinate,
                                                                                          size: Self.snapshotSize)
                }
                guard let snapshot = image, let data = snapshot.jpegData(compressionQuality: 0.8) else {
                    // No coverage here — record the strike, move on
                    self.attach(placeId: place.id, photoUrl: nil) { _ in
                        DispatchQueue.main.async { next() }
                    }
                    return
                }
                PlaceService.shared.uploadImage(data) { uploadResult in
                    guard case .success(let url) = uploadResult else {
                        // Upload hiccup: leave it for a later pass (no strike)
                        DispatchQueue.main.async { next() }
                        return
                    }
                    self.attach(placeId: place.id, photoUrl: url) { didApply in
                        if didApply { applied += 1 }
                        DispatchQueue.main.async { next() }
                    }
                }
            }
        }

        next()
    }

    private func attach(placeId: String, photoUrl: String?, completion: @escaping (Bool) -> Void) {
        var body: [String: Any] = [:]
        if let photoUrl = photoUrl { body["photoUrl"] = photoUrl } else { body["unavailable"] = true }
        APIService.shared.request(
            endpoint: "places/\(placeId)/photo-fallback",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<FallbackResponse, APIError>) in
            if case .success(let response) = result {
                completion(response.data.applied)
            } else {
                completion(false)
            }
        }
    }
}
