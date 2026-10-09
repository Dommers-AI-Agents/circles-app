import UIKit
import CoreLocation

/// First-session location ask (Wes, 2026-10-09: "we want their location —
/// it's important for many aspects of the app"). While-in-use only; the
/// Always upgrade stays tied to "Alert Me at Saved Places".
final class LocationOnboardingViewController: PermissionPrimerViewController, CLLocationManagerDelegate {
    override var symbolName: String { "map.fill" }
    override var headline: String { "Build your map" }
    override var subheadline: String { "FavCircles is your personal map of favorite places — and a window into everyone else's." }
    override var reasons: [Reason] {
        [Reason(symbol: "location.fill", title: "Your map, centered on you",
                detail: "Your places and the places of people you follow, around where you are."),
         Reason(symbol: "mappin.and.ellipse", title: "Save a spot in one tap",
                detail: "We find the place you're standing in, so adding it takes seconds."),
         Reason(symbol: "sparkles", title: "Discover what's nearby",
                detail: "Favorites from people you follow, close to you right now."),
         Reason(symbol: "cloud.sun.fill", title: "Weather, parking, runs and more",
                detail: "Your widgets work where you are.")]
    }
    override var footnote: String? { "Only while you're using the app. Nothing is shared unless you choose to share it." }
    override var allowTitle: String { "Allow Location" }

    private let manager = CLLocationManager()

    /// Only worth showing while iOS hasn't asked yet.
    static var isNeeded: Bool { CLLocationManager().authorizationStatus == .notDetermined }

    override func requestPermission() {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            finish()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let granted = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        AnalyticsService.shared.logEvent("onboarding_location_answered", parameters: ["granted": granted ? "1" : "0"])
        if granted { LocationService.shared.getCurrentLocation { _ in } } // warm the first fix for the map
        DispatchQueue.main.async { self.finish() }
    }
}
