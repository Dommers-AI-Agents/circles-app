import Foundation
import CoreLocation
import UserNotifications

/// "You're at <saved place> — check in?" for people who allow location
/// Always: fires only after the phone has stayed at the place, never for a
/// drive-by.
///
/// How: `CLLocationManager` region monitoring on the nearest saved places
/// (iOS relaunches the app for entry/exit even when force-quit, given
/// Always). Entry arms a local notification `DwellCheckInGate.dwellSeconds`
/// out; exit cancels it. Significant-location-change wakes replan the set
/// as the person moves, so the 20-region cap follows them. Rules live in
/// `DwellCheckInGate`; the day gate, the tap, the actions and the Settings
/// preference are shared with the old entry banner
/// (`ProximityNotificationScheduler`), which stays off.
///
/// When-In-Use users get nothing from this class: `isAvailable` is false and
/// `start()` is a no-op, so they keep the in-app chip only.
final class DwellCheckInMonitor: NSObject {
    static let shared = DwellCheckInMonitor()

    private let manager = CLLocationManager()
    private let center = UNUserNotificationCenter.current()
    private var running = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Availability

    var isAlwaysAuthorized: Bool { manager.authorizationStatus == .authorizedAlways }

    /// Whether the Settings row should offer this at all.
    var isOffered: Bool { isAlwaysAuthorized && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) }

    private func isAvailable(_ completion: @escaping (Bool) -> Void) {
        guard isOffered, AuthService.shared.isLoggedIn else { return completion(false) }
        center.getNotificationSettings { settings in
            let notificationsOK = [.authorized, .provisional].contains(settings.authorizationStatus)
            completion(DwellCheckInGate.isAvailable(isAlwaysAuthorized: true,
                                                     notificationsAuthorized: notificationsOK,
                                                     preferenceOn: ProximityNotificationScheduler.preferenceOn))
        }
    }

    // MARK: - Lifecycle

    /// Called at launch (including a relaunch for a region event: the delegate
    /// is set in `init`, and iOS delivers the pending event once it is) and
    /// whenever the preference flips.
    func start() {
        isAvailable { [weak self] available in
            guard let self else { return }
            DispatchQueue.main.async {
                if available {
                    self.running = true
                    self.manager.startMonitoringSignificantLocationChanges()
                    self.replanFromCache()
                } else {
                    self.stop()
                }
            }
        }
    }

    /// Off: drop the regions and any armed banner. Safe to call when not running.
    func stop() {
        running = false
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions where DwellCheckInGate.placeId(fromIdentifier: region.identifier) != nil {
            manager.stopMonitoring(for: region)
        }
        center.getPendingNotificationRequests { [weak self] pending in
            let ids = pending.map(\.identifier).filter { DwellCheckInGate.placeId(fromIdentifier: $0) != nil }
            if !ids.isEmpty { self?.center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    // MARK: - Planning

    func replanFromCache() {
        guard let userId = AuthService.shared.getUserId() else { return }
        PlacesDiskCache.shared.load(userId: userId) { [weak self] places in
            guard let places, !places.isEmpty else { return }
            self?.replan(places: places, around: LocationService.shared.lastKnownLocation)
        }
    }

    /// Replace the monitored set with the nearest saved places to `around`.
    func replan(places: [Place], around: CLLocation?) {
        guard running, let around else { return }
        let excluded = Set(places.map(\.id).filter { ProximityNotificationScheduler.wasPromptedToday(placeId: $0) })
        let plan = ProximityRegionPlanner.plan(places: places, around: around, excludedPlaceIds: excluded)
        let wanted = Dictionary(uniqueKeysWithValues: plan.map { (DwellCheckInGate.identifierPrefix + $0.placeId, $0) })

        for region in manager.monitoredRegions where DwellCheckInGate.placeId(fromIdentifier: region.identifier) != nil {
            if wanted[region.identifier] == nil { manager.stopMonitoring(for: region) }
        }
        let have = Set(manager.monitoredRegions.map(\.identifier))
        for (identifier, planned) in wanted where !have.contains(identifier) {
            let region = CLCircularRegion(center: planned.coordinate, radius: planned.radius, identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        placeNames.merge(plan.map { ($0.placeId, $0.placeName) }) { _, new in new }
        Logger.debug("📍 Dwell check-in: monitoring \(wanted.count) region(s)")
    }

    /// Names for the banner, remembered across relaunches (a region event may
    /// arrive before the disk cache has been read).
    private var placeNames: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "dwellCheckIn.placeNames") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "dwellCheckIn.placeNames") }
    }

    // MARK: - Arming

    private static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "dwellCheckIn.prompts." + f.string(from: date)
    }

    private func arm(placeId: String) {
        let defaults = UserDefaults.standard
        let context = DwellCheckInGate.EntryContext(
            promptedTodayForPlace: ProximityNotificationScheduler.wasPromptedToday(placeId: placeId),
            promptsToday: defaults.integer(forKey: Self.dayKey()),
            lastArmedAt: defaults.object(forKey: "dwellCheckIn.lastArmedAt") as? Date,
            now: Date()
        )
        guard DwellCheckInGate.shouldArm(context) else {
            Logger.debug("📍 Dwell check-in: entry at \(placeId) stays quiet")
            return
        }
        let name = placeNames[placeId] ?? "a place you saved"
        let content = UNMutableNotificationContent()
        content.title = "You're at \(name)"
        content.body = "Check in and let your people know?"
        content.sound = .default
        content.categoryIdentifier = ProximityNotificationScheduler.categoryIdentifier
        content.threadIdentifier = "proximity-check-in"
        content.userInfo = ["type": ProximityNotificationScheduler.notificationType, "placeId": placeId]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: DwellCheckInGate.dwellSeconds, repeats: false)
        let request = UNNotificationRequest(identifier: DwellCheckInGate.identifierPrefix + placeId, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { Logger.debug("📍 Dwell check-in: arm failed — \(error.localizedDescription)") }
        }
        // Counted when armed; an exit before it fires gives the count back.
        defaults.set(context.promptsToday + 1, forKey: Self.dayKey())
        defaults.set(context.now, forKey: "dwellCheckIn.lastArmedAt")
        ProximityNotificationScheduler.markPromptedToday(placeId: placeId)
        Logger.debug("📍 Dwell check-in: armed \(name), fires in \(Int(DwellCheckInGate.dwellSeconds))s unless they leave")
    }

    private func disarm(placeId: String) {
        let identifier = DwellCheckInGate.identifierPrefix + placeId
        center.getPendingNotificationRequests { [weak self] pending in
            guard pending.contains(where: { $0.identifier == identifier }) else { return }
            self?.center.removePendingNotificationRequests(withIdentifiers: [identifier])
            let defaults = UserDefaults.standard
            defaults.set(max(0, defaults.integer(forKey: Self.dayKey()) - 1), forKey: Self.dayKey())
            defaults.removeObject(forKey: ProximityNotificationScheduler.dayGateKey(placeId: placeId))
            Logger.debug("📍 Dwell check-in: left \(placeId) before the timer — a drive-by, no banner")
        }
    }
}

extension DwellCheckInMonitor: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let placeId = DwellCheckInGate.placeId(fromIdentifier: region.identifier) else { return }
        arm(placeId: placeId)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let placeId = DwellCheckInGate.placeId(fromIdentifier: region.identifier) else { return }
        disarm(placeId: placeId)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Significant-location-change wake: follow the person with the region set.
        guard running, let userId = AuthService.shared.getUserId(), let here = locations.last else { return }
        PlacesDiskCache.shared.load(userId: userId) { [weak self] places in
            guard let places, !places.isEmpty else { return }
            self?.replan(places: places, around: here)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Always granted or revoked in Settings: come up or go quiet.
        start()
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Logger.debug("📍 Dwell check-in: monitoring failed for \(region?.identifier ?? "?") — \(error.localizedDescription)")
    }
}
