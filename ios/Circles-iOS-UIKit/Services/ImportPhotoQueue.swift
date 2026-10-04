import Foundation
import MapKit
import UIKit

/// Background pass that gives photo-less places a photo for free — imports,
/// and saves made without waiting for a photo (needsPhoto).
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
        /// Ask the server for the place's Google photo first (a save made
        /// without a photo; never imports). Absent on older servers.
        let tryGoogle: Bool?
    }

    private struct DefaultPhotoResponse: Decodable {
        struct Payload: Decodable { let applied: Bool; let reason: String? }
        let success: Bool
        let data: Payload
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
        // Signal back → finish what a weak signal interrupted
        NotificationCenter.default.addObserver(forName: .networkReachabilityDidChange, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[NetworkMonitor.isConnectedKey] as? Bool) ?? NetworkMonitor.shared.isConnected { self?.kick() }
        }
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
        // Kept saves, then your own photos waiting to upload, go first
        // (same launch/foreground/reconnect triggers)
        PlaceSaveOutbox.shared.drain()
        PlacePhotoOutbox.shared.drain()
        DispatchQueue.main.async {
            guard #available(iOS 16.0, *) else { return }
            guard !self.isRunning else { return }
            guard AuthService.shared.isLoggedIn else { return }
            guard UIApplication.shared.applicationState != .background else { return }
            guard NetworkMonitor.shared.isConnected else { return }
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
            // Lost the signal mid-pass: stop without counting anything
            // against these places; the reconnect picks up from here.
            guard NetworkMonitor.shared.isConnected else { finish(interrupted: true); return }
            let place = places[index]
            index += 1
            // The saver's own photo is still waiting to upload — let it land
            if PlacePhotoOutbox.shared.hasPending(placeId: place.id) { next(); return }
            let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)

            // The place's own Google photo is the default (Wes, 2026-10-04);
            // Look Around, then a map, only when Google has none
            if place.tryGoogle == true {
                self.googleDefaultPhoto(placeId: place.id) { outcome in
                    DispatchQueue.main.async {
                        switch outcome {
                        case .added: applied += 1; next()
                        case .noGooglePhoto: onDevicePhoto(place, coordinate)
                        case .done, .later: next()   // already pictured / try again on a later pass
                        }
                    }
                }
                return
            }
            onDevicePhoto(place, coordinate)
        }

        func onDevicePhoto(_ place: PhotoCandidate, _ coordinate: CLLocationCoordinate2D) {
            Task {
                var image: UIImage?
                if await AppleLookAroundService.shared.checkLookAroundAvailability(at: coordinate) {
                    image = try? await AppleLookAroundService.shared.getLookAroundSnapshot(at: coordinate,
                                                                                          size: Self.snapshotSize)
                }
                // No street view here: an Apple map of the spot, so no saved
                // place is left without a picture (Wes, 2026-10-04)
                if image == nil { image = await PlaceMapSnapshot.render(at: coordinate, size: Self.snapshotSize) }
                guard let snapshot = image, let data = snapshot.jpegData(compressionQuality: 0.8) else {
                    // Online and still nothing (rare): count a strike. Offline:
                    // leave it for the reconnect.
                    guard NetworkMonitor.shared.isConnected else { DispatchQueue.main.async { next() }; return }
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

    enum GoogleOutcome { case added, noGooglePhoto, done, later }

    /// Only "Google has none" sends a place on to Look Around / a map; an
    /// already-pictured place is done, and anything else (no signal, a
    /// place unsaved meanwhile) waits for a later pass.
    private func googleDefaultPhoto(placeId: String, completion: @escaping (GoogleOutcome) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(placeId)/default-photo",
            method: .post,
            requiresAuth: true
        ) { (result: Result<DefaultPhotoResponse, APIError>) in
            switch result {
            case .success(let response) where response.data.applied: completion(.added)
            case .success(let response):
                switch response.data.reason {
                case "no_google_photo", "not_eligible": completion(.noGooglePhoto)
                default: completion(.done)    // has_photo / venue_has_photo
                }
            case .failure: completion(.later)
            }
        }
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
