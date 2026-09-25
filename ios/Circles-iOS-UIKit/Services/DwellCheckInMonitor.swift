import Foundation
import CoreLocation
import UIKit
import UserNotifications

/// "You're at <saved place> — check in?" for people who allow location
/// Always: fires when they walk IN, never for a drive-by.
///
/// How: `CLLocationManager` region monitoring on the nearest saved places
/// (iOS relaunches the app for entry/exit even when force-quit, given
/// Always) is only the alarm clock — a 100 m region computed from coarse
/// position says "somewhere near". On entry this class takes GPS fixes and
/// hands them to `ArrivalVerifier`, which answers the moment two good fixes
/// put the phone at the venue at walking pace; a fix that says driving, or
/// already outside, ends the watch with nothing. Nothing is scheduled ahead
/// of time: if the process dies mid-watch, no banner and nothing consumed.
///
/// From the second banner of a day the notification carries "Turn off
/// reminders" (`CHECK_IN_PROMPT_OPTOUT`), so nobody is worn down by it.
///
/// Rules (once per place per day, a daily cap, a global cooldown) live in
/// `DwellCheckInGate`; the day gate, tap and actions are shared with the old
/// entry banner (`ProximityNotificationScheduler`), which stays off.
/// When-In-Use users get nothing from this class: `isAvailable` is false and
/// `start()` is a no-op, so they keep the in-app chip only.
final class DwellCheckInMonitor: NSObject {
    static let shared = DwellCheckInMonitor()

    private let manager = CLLocationManager()
    private let center = UNUserNotificationCenter.current()
    private var running = false

    /// Bounces on a region edge would restart the watch over and over;
    /// one watch per place per this window.
    private static let perPlaceGuard: TimeInterval = 10 * 60
    private var recentWatchStarts: [String: Date] = [:]

    private struct Watch {
        let placeId: String
        var verifier: ArrivalVerifier
        let deadline: DispatchSourceTimer
        var backgroundTask: UIBackgroundTaskIdentifier
        var lastFix: CLLocation?
    }
    private var watch: Watch?

    private override init() {
        super.init()
        manager.delegate = self
        // The watch runs with the app in the background (Info.plist has the
        // `location` mode); GPS-grade fixes are what make "at the door" and
        // "driving" mean anything — WiFi/cell fixes carry no speed.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
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
        // Leftover blind timers from the 09-24 build, whatever else happens.
        sweepPendingRequests()
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

    /// Off: end any watch, drop the regions. Safe to call when not running.
    func stop() {
        abortWatch(reason: "stopped")
        running = false
        manager.stopMonitoringSignificantLocationChanges()
        for region in manager.monitoredRegions where DwellCheckInGate.placeId(fromIdentifier: region.identifier) != nil {
            manager.stopMonitoring(for: region)
        }
        sweepPendingRequests()
    }

    private func sweepPendingRequests() {
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
            // cachedLocation, not lastKnownLocation: after a relaunch for a
            // region event the latter is nil and the plan would never happen.
            self?.replan(places: places, around: LocationService.shared.cachedLocation)
        }
    }

    /// Replace the monitored set with the nearest saved places to `around`.
    /// A place under watch is pinned: it stays monitored (so its exit can
    /// still end the watch) whatever the plan says.
    func replan(places: [Place], around: CLLocation?) {
        guard running, let around else { return }
        let pinned: Set<String> = watch.map { [$0.placeId] } ?? []
        let excluded = Set(places.map(\.id).filter { ProximityNotificationScheduler.wasPromptedToday(placeId: $0) })
        let plan = ProximityRegionPlanner.plan(places: places, around: around, excludedPlaceIds: excluded, pinnedPlaceIds: pinned)
        let wanted = Dictionary(uniqueKeysWithValues: plan.map { (DwellCheckInGate.identifierPrefix + $0.placeId, $0) })

        for region in manager.monitoredRegions {
            guard let placeId = DwellCheckInGate.placeId(fromIdentifier: region.identifier) else { continue }
            if wanted[region.identifier] == nil && !pinned.contains(placeId) { manager.stopMonitoring(for: region) }
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

    // MARK: - Accounting

    private static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "dwellCheckIn.prompts." + f.string(from: date)
    }

    private func entryContext(placeId: String, now: Date = Date()) -> DwellCheckInGate.EntryContext {
        let defaults = UserDefaults.standard
        return DwellCheckInGate.EntryContext(
            promptedTodayForPlace: ProximityNotificationScheduler.wasPromptedToday(placeId: placeId),
            promptsToday: defaults.integer(forKey: Self.dayKey(now)),
            lastFiredAt: defaults.object(forKey: "dwellCheckIn.lastFiredAt") as? Date,
            now: now
        )
    }

    // MARK: - The watch

    /// Region entry: the wake-up. Must not depend on `running` — on a
    /// relaunch for the event, `start()`'s settings callback is still in
    /// flight when the event lands.
    private func beginWatch(region: CLCircularRegion, placeId: String) {
        guard watch == nil else {
            Logger.debug("📍 Dwell check-in: entered \(placeId) while watching \(watch!.placeId) — ignored")
            return
        }
        guard isOffered, ProximityNotificationScheduler.preferenceOn, AuthService.shared.isLoggedIn else { return }
        let now = Date()
        if let last = recentWatchStarts[placeId], now.timeIntervalSince(last) < Self.perPlaceGuard {
            Logger.debug("📍 Dwell check-in: \(placeId) re-entered within \(Int(Self.perPlaceGuard))s — ignored")
            return
        }
        guard DwellCheckInGate.shouldPrompt(entryContext(placeId: placeId, now: now)) else {
            Logger.debug("📍 Dwell check-in: entry at \(placeId) stays quiet")
            return
        }
        recentWatchStarts[placeId] = now

        let task = UIApplication.shared.beginBackgroundTask(withName: "dwellCheckIn.watch") { [weak self] in
            self?.abortWatch(reason: "background task expired")
        }
        let deadline = DispatchSource.makeTimerSource(queue: .main)
        deadline.schedule(deadline: .now() + ArrivalVerifier.Thresholds.maxWatch)
        deadline.setEventHandler { [weak self] in self?.deadlineReached() }
        watch = Watch(placeId: placeId,
                      verifier: ArrivalVerifier(center: region.center, radius: region.radius, startedAt: now),
                      deadline: deadline,
                      backgroundTask: task,
                      lastFix: nil)
        deadline.resume()
        manager.startUpdatingLocation()
        Logger.debug("📍 Dwell check-in: watching \(placeNames[placeId] ?? placeId) for an arrival")
    }

    private func observe(_ fixes: [CLLocation]) {
        guard watch != nil else { return }
        for fix in fixes {
            watch?.lastFix = fix
            let verdict = watch!.verifier.observe(fix)
            Logger.debug("📍 Dwell check-in: fix ±\(Int(fix.horizontalAccuracy))m, \(Int(fix.distance(from: watch!.verifier.center)))m from pin → \(verdict)")
            switch verdict {
            case .watching: continue
            case .arrived: fire(placeId: watch!.placeId); return
            case .leftRegion, .driving, .inconclusive: abortWatch(reason: "\(verdict)"); return
            }
        }
    }

    private func deadlineReached() {
        // The one-shot timer is spent either way; never leave GPS running.
        guard watch != nil else { return }
        watch!.verifier.deadlineReached(at: Date())
        abortWatch(reason: "no arrival within the window")
    }

    private func fire(placeId: String) {
        // In the foreground the home chip owns this; a stamp here would
        // suppress it.
        if UIApplication.shared.applicationState == .active {
            Logger.debug("📍 Dwell check-in: arrived at \(placeId) with the app open — the chip's job")
            endWatch()
            return
        }
        let now = Date()
        let context = entryContext(placeId: placeId, now: now)
        guard DwellCheckInGate.shouldPrompt(context) else {
            Logger.debug("📍 Dwell check-in: arrived at \(placeId) but the day's rules say quiet")
            endWatch()
            return
        }
        let name = placeNames[placeId] ?? "a place you saved"
        let offersOptOut = DwellCheckInGate.offersOptOut(promptsToday: context.promptsToday)
        let content = UNMutableNotificationContent()
        content.title = "You're at \(name)"
        content.body = offersOptOut
            ? "Check in and let your people know? Getting too many? Tap Turn off reminders any time."
            : "Check in and let your people know?"
        content.sound = .default
        content.categoryIdentifier = offersOptOut
            ? ProximityNotificationScheduler.optOutCategoryIdentifier
            : ProximityNotificationScheduler.categoryIdentifier
        content.threadIdentifier = "proximity-check-in"
        content.userInfo = ["type": ProximityNotificationScheduler.notificationType, "placeId": placeId]
        let request = UNNotificationRequest(identifier: DwellCheckInGate.identifierPrefix + placeId, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Logger.debug("📍 Dwell check-in: post failed — \(error.localizedDescription)")
                return
            }
            // Consumed only once the banner is actually out.
            let defaults = UserDefaults.standard
            defaults.set(context.promptsToday + 1, forKey: Self.dayKey(now))
            defaults.set(now, forKey: "dwellCheckIn.lastFiredAt")
            ProximityNotificationScheduler.markPromptedToday(placeId: placeId)
            Logger.debug("📍 Dwell check-in: banner for \(name)\(offersOptOut ? " with the turn-off offer" : "")")
        }
        endWatch()
    }

    private func abortWatch(reason: String) {
        guard watch != nil else { return }
        Logger.debug("📍 Dwell check-in: watch on \(watch!.placeId) ended — \(reason)")
        endWatch()
    }

    private func endWatch() {
        guard let current = watch else { return }
        manager.stopUpdatingLocation()
        current.deadline.cancel()
        if current.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(current.backgroundTask) }
        watch = nil
        // The region set may have drifted while the watch pinned this place.
        if running, let userId = AuthService.shared.getUserId() {
            let around = current.lastFix ?? LocationService.shared.cachedLocation
            PlacesDiskCache.shared.load(userId: userId) { [weak self] places in
                guard let places, !places.isEmpty else { return }
                self?.replan(places: places, around: around)
            }
        }
    }
}

extension DwellCheckInMonitor: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let placeId = DwellCheckInGate.placeId(fromIdentifier: region.identifier),
              let circular = region as? CLCircularRegion else { return }
        beginWatch(region: circular, placeId: placeId)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let placeId = DwellCheckInGate.placeId(fromIdentifier: region.identifier) else { return }
        if watch?.placeId == placeId { abortWatch(reason: "left the region") }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if watch != nil {
            observe(locations)
            return
        }
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
