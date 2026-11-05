import Foundation
import AlarmKit
import AppIntents

// Shared by the app and the Circles-Widget extension (membership exception
// in the project): what a Wake Up alarm carries, and its buttons' actions.
// Stop wakes you and opens the station; Snooze counts down and rings again.

@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {
    var title: String
    var stationName: String?
    var stationURL: String?
}

extension Notification.Name {
    /// Posted in the app when an alarm's Stop (or the snooze screen's Play
    /// now) asks for the station; `object` is the link.
    static let wakeAlarmPlayStation = Notification.Name("WakeAlarmPlayStation")
}

/// Where the station link waits until the app is in front to open it, with
/// when it was asked for: a stale one (the person never opened the app)
/// must not start music hours later.
enum WakeAlarmHandoffStore {
    static let key = "wakeAlarmPendingStation"
    static let atKey = "wakeAlarmPendingStationAt"
    static let nameKey = "wakeAlarmPendingStationName"
}

/// Stop: ends the alarm, then the app opens and plays the station (Wes,
/// 2026-11-05). Runs in the app's process.
@available(iOS 26.0, *)
struct WakeUpPlayStationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Wake up and play station"
    static var isDiscoverable = false
    static var openAppWhenRun = true

    @Parameter(title: "Alarm") var alarmID: String
    @Parameter(title: "Station link") var stationURL: String
    @Parameter(title: "Station") var stationName: String

    init() {}

    init(alarmID: String, stationURL: String, stationName: String) {
        self.alarmID = alarmID
        self.stationURL = stationURL
        self.stationName = stationName
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.stop(id: id) }
        if !stationURL.isEmpty {
            UserDefaults.standard.set(stationURL, forKey: WakeAlarmHandoffStore.key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WakeAlarmHandoffStore.atKey)
            UserDefaults.standard.set(stationName, forKey: WakeAlarmHandoffStore.nameKey)
            let link = stationURL
            await MainActor.run { NotificationCenter.default.post(name: .wakeAlarmPlayStation, object: link) }
        }
        return .result()
    }
}

/// Snooze: counts down the alarm's snooze minutes, then it rings again.
@available(iOS 26.0, *)
struct WakeUpSnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze alarm"
    static var isDiscoverable = false

    @Parameter(title: "Alarm") var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try? AlarmManager.shared.countdown(id: id) }
        return .result()
    }
}
