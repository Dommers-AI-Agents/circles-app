import Foundation
import FavWidgetsCore

/// Wake Up's real alarms (contract 0.60.0): AlarmKit on iOS 26+, nothing
/// before (the widget explains it needs a newer iOS).
extension AppWidgetHost {
    func alarmPermission() async -> WidgetAlarmPermission {
        guard #available(iOS 26.0, *) else { return .unavailable }
        return WakeAlarmScheduler.permission
    }

    func requestAlarmPermission() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return await WakeAlarmScheduler.requestPermission()
    }

    func syncAlarms(_ alarms: [WidgetAlarmSpec]) async throws {
        guard #available(iOS 26.0, *) else { return }
        try await WakeAlarmScheduler.sync(alarms)
    }
}
