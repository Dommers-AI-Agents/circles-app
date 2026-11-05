import Foundation
import UIKit
import SwiftUI
import AlarmKit
import UserNotifications
import FavWidgetsCore

/// Sets the phone's real alarms for the Wake Up widget (AlarmKit, iOS 26+).
/// Each alarm keeps its widget id, so setting it again replaces it; alarms
/// the widget no longer has are cancelled. An alarm that's ringing or
/// snoozing is left alone so a sync never cuts a snooze short.
@available(iOS 26.0, *)
enum WakeAlarmScheduler {
    /// What each alarm was last set with, so unchanged alarms aren't re-set
    private static let fingerprintsKey = "wakeAlarmFingerprints"
    private static let tint = Color(red: 0.94, green: 0.54, blue: 0.14)

    static var permission: WidgetAlarmPermission {
        switch AlarmManager.shared.authorizationState {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .allowed
        @unknown default: return .denied
        }
    }

    static func requestPermission() async -> Bool {
        (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }

    static func sync(_ specs: [WidgetAlarmSpec]) async throws {
        let manager = AlarmManager.shared
        let existing = (try? manager.alarms) ?? []
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var fingerprints = UserDefaults.standard.dictionary(forKey: fingerprintsKey) as? [String: String] ?? [:]
        let wanted = Dictionary(specs.compactMap { spec in UUID(uuidString: spec.id).map { ($0, spec) } },
                                uniquingKeysWith: { a, _ in a })

        // Gone from the widget (or switched off): cancel
        for alarm in existing where wanted[alarm.id] == nil {
            try? manager.cancel(id: alarm.id)
            fingerprints[alarm.id.uuidString] = nil
        }

        for (id, spec) in wanted {
            let fingerprint = Self.fingerprint(spec)
            if let current = byId[id] {
                // Ringing or snoozing: leave it be
                if current.state != .scheduled { continue }
                if fingerprints[id.uuidString] == fingerprint { continue }
                try? manager.cancel(id: id)
            }
            _ = try await manager.schedule(id: id, configuration: configuration(spec, id: id))
            fingerprints[id.uuidString] = fingerprint
        }
        UserDefaults.standard.set(fingerprints, forKey: fingerprintsKey)
    }

    private static func configuration(_ spec: WidgetAlarmSpec, id: UUID) -> AlarmManager.AlarmConfiguration<WakeAlarmMetadata> {
        let station = spec.stationName.map { "Play \($0)" }
        let snooze = spec.snoozeMinutes > 0
            ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz") : nil
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: spec.title),
                                            secondaryButton: snooze, secondaryButtonBehavior: snooze == nil ? nil : .countdown)
        } else {
            alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: spec.title),
                                            stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: station ?? "Stop"),
                                                                    textColor: .white, systemImageName: "stop.fill"),
                                            secondaryButton: snooze, secondaryButtonBehavior: snooze == nil ? nil : .countdown)
        }
        let countdown = AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: "Snoozing · \(spec.title)"))
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert, countdown: spec.snoozeMinutes > 0 ? countdown : nil),
            metadata: WakeAlarmMetadata(title: spec.title, stationName: spec.stationName, stationURL: spec.stationURL?.absoluteString),
            tintColor: tint)

        let weekdays = spec.weekdays.compactMap(Self.weekday)
        let schedule = Alarm.Schedule.relative(.init(time: .init(hour: spec.hour, minute: spec.minute),
                                                     repeats: weekdays.isEmpty ? .never : .weekly(weekdays)))
        return AlarmManager.AlarmConfiguration(
            countdownDuration: spec.snoozeMinutes > 0
                ? Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(spec.snoozeMinutes * 60)) : nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: WakeUpPlayStationIntent(alarmID: id.uuidString, stationURL: spec.stationURL?.absoluteString ?? "",
                                                stationName: spec.stationName ?? ""),
            secondaryIntent: spec.snoozeMinutes > 0 ? WakeUpSnoozeIntent(alarmID: id.uuidString) : nil)
    }

    /// 1 = Sunday … 7 = Saturday
    private static func weekday(_ day: Int) -> Locale.Weekday? {
        switch day {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    private static func fingerprint(_ spec: WidgetAlarmSpec) -> String {
        [spec.hour, spec.minute, spec.snoozeMinutes].map(String.init).joined(separator: ":")
            + "|\(spec.weekdays.sorted())|\(spec.title)|\(spec.stationName ?? "")|\(spec.stationURL?.absoluteString ?? "")"
    }
}

/// Opens the station an alarm's Stop asked for, once the app is in front.
/// If iOS didn't bring the app forward, a notification offers the station
/// instead (tapping it opens the app, which then opens the station).
@MainActor
final class WakeAlarmHandoff {
    static let shared = WakeAlarmHandoff()
    private var started = false
    /// How long after Stop the station still opens by itself
    private let freshFor: TimeInterval = 15 * 60

    /// Called at launch: listens for Stop and for the app coming forward.
    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .wakeAlarmPlayStation, object: nil, queue: .main) { _ in
            Task { @MainActor in
                WakeAlarmHandoff.shared.openPending()
                // Still in the background a moment later: offer it as a notification
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                WakeAlarmHandoff.shared.offerIfStillPending()
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in WakeAlarmHandoff.shared.openPending() }
        }
        openPending()
    }

    private var pending: (url: URL, name: String)? {
        let defaults = UserDefaults.standard
        guard let link = defaults.string(forKey: WakeAlarmHandoffStore.key), let url = URL(string: link) else { return nil }
        let at = defaults.double(forKey: WakeAlarmHandoffStore.atKey)
        guard Date().timeIntervalSince1970 - at < freshFor else {
            clearPending()
            return nil
        }
        return (url, defaults.string(forKey: WakeAlarmHandoffStore.nameKey) ?? "")
    }

    private func clearPending() {
        [WakeAlarmHandoffStore.key, WakeAlarmHandoffStore.atKey, WakeAlarmHandoffStore.nameKey]
            .forEach(UserDefaults.standard.removeObject(forKey:))
    }

    private func offerIfStillPending() {
        guard UIApplication.shared.applicationState != .active, let pending else { return }
        let content = UNMutableNotificationContent()
        content.title = pending.name.isEmpty ? "Good morning ☀️" : "▶︎ Play \(pending.name)"
        content.body = "Tap to start your station."
        content.sound = nil
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["type": "wake_alarm_station"]
        let request = UNNotificationRequest(identifier: "wake-alarm-station", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func openPending() {
        guard UIApplication.shared.applicationState == .active, let pending else { return }
        clearPending()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["wake-alarm-station"])
        let url = pending.url
        AnalyticsService.shared.logEvent("wakeup_station_opened", parameters: ["host": url.host ?? url.scheme ?? ""])
        UIApplication.shared.open(url)
    }
}
