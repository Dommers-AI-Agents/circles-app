import Foundation
import FavWidgetsCore

extension AppWidgetHost {
    func runLiveActivity(_ update: WidgetRunLiveUpdate?) {
        guard #available(iOS 16.2, *) else { return }   // older iOS: no lock-screen display
        Task { @MainActor in RunLiveActivityController.shared.apply(update) }
    }
}
