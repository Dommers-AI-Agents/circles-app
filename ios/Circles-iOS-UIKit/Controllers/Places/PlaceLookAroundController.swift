import UIKit
import CoreLocation

/// What the place page does when Look Around state changes. All callbacks
/// arrive on the main actor.
protocol PlaceLookAroundControllerDelegate: AnyObject {
    func currentPlace(for controller: PlaceLookAroundController) -> Place
    /// `isAvailable` was (re)determined — refresh the toggle button.
    func lookAroundAvailabilityDidChange(_ controller: PlaceLookAroundController)
    /// A snapshot requested for the toggle finished loading.
    func lookAroundImageDidLoad(_ controller: PlaceLookAroundController)
    /// The on-open auto-load finished: image is set and `isAvailable` is
    /// true; the page decides whether to show it (no photos) or keep it
    /// behind the toggle.
    func lookAroundDidAutoLoad(_ controller: PlaceLookAroundController)
}

/// Apple Look Around for the place page: availability, the street-level
/// snapshot, and whether it is currently shown in the carousel. The page
/// owns the UI; this owns the fetches and the three flags.
@MainActor
final class PlaceLookAroundController {
    weak var delegate: PlaceLookAroundControllerDelegate?

    var image: UIImage?
    var isAvailable = false
    var isShowing = false

    func checkAvailability() {
        guard let place = delegate?.currentPlace(for: self) else { return }
        guard let location = place.location?.clLocation else {
            Logger.debug("⚠️ PlaceDetailViewController: No location available for street view check")
            return
        }

        if #available(iOS 16.0, *) {
            Logger.debug("🔍 PlaceDetailViewController: Checking Look Around availability for \(place.name)")
            Task {
                let available = await AppleLookAroundService.shared.checkLookAroundAvailability(at: location.coordinate)
                await MainActor.run {
                    Logger.debug("📍 PlaceDetailViewController: Look Around available: \(available)")
                    self.isAvailable = available
                    self.delegate?.lookAroundAvailabilityDidChange(self)
                }
            }
        } else {
            // Look Around not available on iOS < 16
            Logger.debug("⚠️ PlaceDetailViewController: iOS < 16.0, Look Around not available")
            isAvailable = false
            delegate?.lookAroundAvailabilityDidChange(self)
        }
    }

    /// Fetches the snapshot for the toggle (200pt tall).
    func loadImage() {
        guard let place = delegate?.currentPlace(for: self) else { return }
        guard let location = place.location?.clLocation else { return }

        if #available(iOS 16.0, *) {
            let imageSize = CGSize(width: UIScreen.main.bounds.width, height: 200)

            Task {
                do {
                    let image = try await AppleLookAroundService.shared.getLookAroundSnapshot(
                        at: location.coordinate,
                        size: imageSize
                    )
                    await MainActor.run {
                        self.image = image
                        self.delegate?.lookAroundImageDidLoad(self)
                    }
                } catch {
                    Logger.debug("Failed to load Look Around: \(error)")
                }
            }
        }
    }

    /// On open: if Look Around exists here, fetch a taller snapshot (300pt)
    /// so a place without photos has something to show.
    func autoLoad() {
        // Idempotent: configureUI re-runs on server refresh; one fetch is enough
        guard image == nil else { return }
        guard let place = delegate?.currentPlace(for: self) else { return }
        guard let location = place.location?.clLocation else { return }

        if #available(iOS 16.0, *) {
            Task {
                // Check if Look Around is available first
                let available = await AppleLookAroundService.shared.checkLookAroundAvailability(at: location.coordinate)
                guard available else { return }

                let imageSize = CGSize(width: UIScreen.main.bounds.width, height: 300)

                do {
                    let image = try await AppleLookAroundService.shared.getLookAroundSnapshot(
                        at: location.coordinate,
                        size: imageSize
                    )
                    await MainActor.run {
                        self.image = image
                        self.isAvailable = true
                        self.delegate?.lookAroundDidAutoLoad(self)
                    }
                } catch {
                    Logger.error("Failed to auto-load Look Around: \(error)")
                }
            }
        }
    }
}
