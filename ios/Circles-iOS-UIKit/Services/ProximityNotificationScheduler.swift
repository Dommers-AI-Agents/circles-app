import Foundation
import CoreLocation
import UserNotifications

/// Schedules the "you're near <saved place>, check in?" system banner.
///
/// Uses `UNLocationNotificationTrigger`: iOS monitors the regions on the app's
/// behalf and delivers the banner even when the app is force-quit, with only
/// the When-In-Use location permission the app already holds. No app code
/// runs on delivery, so:
/// - requests are `repeats: false` (a fired one is consumed) and the plan is
///   rebuilt whenever the app comes forward or the saved set changes;
/// - the once-per-place-per-day throttle is the same UserDefaults gate the
///   in-app chip uses (`proximityCheckInPrompted.<placeId>.<day>`), stamped
///   on tap / "Not now" and for banners still sitting in Notification Center.
///
/// The tap opens the check-in sheet pre-filled (`NavigateToCheckIn`); a
/// one-tap check-in isn't possible because the backend requires a recipient.
final class ProximityNotificationScheduler {
    static let shared = ProximityNotificationScheduler()

    static let notificationType = "proximity_check_in"
    static let categoryIdentifier = "CHECK_IN_PROMPT"
    static let checkInAction = "CHECK_IN"
    static let notNowAction = "NOT_NOW"

    /// Device-local mirror of `NotificationPreferences.locationPrompts`, so the
    /// gate works before the profile has loaded. Absent = on.
    static let preferenceKey = "proximityCheckInBannersEnabled"

    private let center = UNUserNotificationCenter.current()
    private let minimumReplanInterval: TimeInterval = 5 * 60
    private var lastReplanAt: Date?

    private init() {}

    // MARK: - Preference

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    /// Called by the preferences screen. Off cancels immediately; on replans
    /// from the disk cache.
    func setEnabled(_ enabled: Bool) {
        Self.isEnabled = enabled
        if enabled {
            replanFromCache(force: true)
        } else {
            cancelAll()
        }
    }

    // MARK: - Day gate (shared with the in-app chip)

    static func dayGateKey(placeId: String, on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "proximityCheckInPrompted.\(placeId).\(formatter.string(from: date))"
    }

    static func markPromptedToday(placeId: String) {
        UserDefaults.standard.set(true, forKey: dayGateKey(placeId: placeId))
    }

    static func wasPromptedToday(placeId: String) -> Bool {
        UserDefaults.standard.bool(forKey: dayGateKey(placeId: placeId))
    }

    // MARK: - Planning

    /// Rebuild the monitored set from the disk cache, using the last fix the
    /// app has. Cheap enough to call after any save.
    func replanFromCache(force: Bool = false) {
        guard let userId = AuthService.shared.getUserId() else { return }
        PlacesDiskCache.shared.load(userId: userId) { [weak self] places in
            guard let places = places else { return }
            self?.replan(places: places, around: LocationService.shared.lastKnownLocation, force: force)
        }
    }

    /// Replace every pending proximity request with a fresh plan around
    /// `around`. Skipped (plan left as is) when a gate fails or when nothing
    /// forced it within the last five minutes.
    func replan(places: [Place], around: CLLocation?, force: Bool = false) {
        guard AuthService.shared.isLoggedIn, Self.isEnabled else {
            cancelAll()
            return
        }
        guard let around = around else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              [.authorizedWhenInUse, .authorizedAlways].contains(CLLocationManager().authorizationStatus) else {
            return
        }
        if !force, let last = lastReplanAt, Date().timeIntervalSince(last) < minimumReplanInterval {
            return
        }
        lastReplanAt = Date()

        center.getNotificationSettings { [weak self] settings in
            guard let self = self,
                  [.authorized, .provisional].contains(settings.authorizationStatus) else { return }

            // A banner the user hasn't dealt with yet counts as today's prompt
            self.center.getDeliveredNotifications { delivered in
                for note in delivered {
                    if let placeId = ProximityRegionPlanner.placeId(fromIdentifier: note.request.identifier) {
                        Self.markPromptedToday(placeId: placeId)
                    }
                }

                let excluded = Set(places.map { $0.id }.filter { Self.wasPromptedToday(placeId: $0) })
                let plan = ProximityRegionPlanner.plan(places: places, around: around, excludedPlaceIds: excluded)

                self.removePendingProximityRequests {
                    for region in plan {
                        self.center.add(self.makeRequest(for: region)) { error in
                            if let error = error {
                                Logger.debug("📍 Proximity banner: add failed for \(region.placeName) — \(error.localizedDescription)")
                            }
                        }
                    }
                    Logger.debug("📍 Proximity banner: planned \(plan.count) region(s) around \(around.coordinate.latitude), \(around.coordinate.longitude)")
                }
            }
        }
    }

    /// Drop every proximity request, pending and delivered (logout, toggle off).
    func cancelAll() {
        lastReplanAt = nil
        removePendingProximityRequests {}
        center.getDeliveredNotifications { [weak self] delivered in
            let ids = delivered.map { $0.request.identifier }
                .filter { ProximityRegionPlanner.placeId(fromIdentifier: $0) != nil }
            if !ids.isEmpty { self?.center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    // MARK: - Requests

    private func removePendingProximityRequests(then completion: @escaping () -> Void) {
        center.getPendingNotificationRequests { [weak self] pending in
            let ids = pending.map { $0.identifier }
                .filter { ProximityRegionPlanner.placeId(fromIdentifier: $0) != nil }
            if !ids.isEmpty { self?.center.removePendingNotificationRequests(withIdentifiers: ids) }
            completion()
        }
    }

    private func makeRequest(for region: ProximityRegionPlanner.PlannedRegion) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = region.placeName
        content.body = "You're nearby. Check in and let your people know?"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "proximity-check-in"
        content.userInfo = ["type": Self.notificationType, "placeId": region.placeId]

        let circle = CLCircularRegion(center: region.coordinate, radius: region.radius, identifier: region.identifier)
        circle.notifyOnEntry = true
        circle.notifyOnExit = false
        let trigger = UNLocationNotificationTrigger(region: circle, repeats: false)

        return UNNotificationRequest(identifier: region.identifier, content: content, trigger: trigger)
    }
}
