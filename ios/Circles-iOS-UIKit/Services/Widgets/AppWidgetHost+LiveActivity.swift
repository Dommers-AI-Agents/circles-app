import Foundation
import FavWidgetsCore

extension AppWidgetHost {
    func runLiveActivity(_ update: WidgetRunLiveUpdate?) {
        guard #available(iOS 16.2, *) else { return }   // older iOS: no lock-screen display
        Task { @MainActor in RunLiveActivityController.shared.apply(update) }
    }
}

extension AppWidgetHost {
    func startEventLiveActivity(_ event: WidgetEventLiveStart) async -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        return await MainActor.run { EventLiveActivityController.shared.start(event) }
    }

    func stopEventLiveActivity(eventId: String) async {
        guard #available(iOS 16.2, *) else { return }
        await EventLiveActivityController.shared.stop(eventId)
    }

    func isEventLiveActivityOn(eventId: String) -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        return MainActor.assumeIsolated { EventLiveActivityController.shared.isOn(eventId) }
    }
}
